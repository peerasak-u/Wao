import Foundation

public enum StoredZipError: Error, Equatable {
    case notAZip
    case unsupported(String)
    case truncated
    case crcMismatch(String)
}

/// Reads zips whose entries are stored (method 0), as the model's `.asr.zip` is. No zip64.
public struct StoredZip {
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let size: UInt64
        public let crc32: UInt32
        let localHeaderOffset: UInt64
    }

    public let url: URL
    public let entries: [Entry]

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()

        let tailLength = min(fileSize, 22 + 65_535)
        try handle.seek(toOffset: fileSize - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let eocd = Self.lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: tail) else { throw StoredZipError.notAZip }
        let count = Int(tail.le16(eocd + 10))
        let directorySize = UInt64(tail.le32(eocd + 12))
        let directoryOffset = UInt64(tail.le32(eocd + 16))
        guard directoryOffset + directorySize <= fileSize else { throw StoredZipError.truncated }

        try handle.seek(toOffset: directoryOffset)
        let directory = try handle.read(upToCount: Int(directorySize)) ?? Data()
        var entries: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= directory.count, directory.le32(p) == 0x0201_4B50 else { throw StoredZipError.truncated }
            let method = directory.le16(p + 10)
            let crc = directory.le32(p + 16)
            let compressed = UInt64(directory.le32(p + 20))
            let size = UInt64(directory.le32(p + 24))
            let nameLength = Int(directory.le16(p + 28))
            let extraLength = Int(directory.le16(p + 30))
            let commentLength = Int(directory.le16(p + 32))
            let offset = UInt64(directory.le32(p + 42))
            guard p + 46 + nameLength <= directory.count else { throw StoredZipError.truncated }
            let name = String(decoding: directory[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            guard method == 0, compressed == size else { throw StoredZipError.unsupported("\(name): method \(method)") }
            guard size != 0xFFFF_FFFF, offset != 0xFFFF_FFFF else { throw StoredZipError.unsupported("zip64") }
            entries.append(Entry(name: name, size: size, crc32: crc, localHeaderOffset: offset))
            p += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// Streams the entry to `destination` through a temporary file, verifying its CRC-32 before the rename,
    /// so `destination` either holds the whole verified entry or is left untouched.
    public func extract(_ entry: Entry, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        try input.seek(toOffset: entry.localHeaderOffset)
        guard let header = try input.read(upToCount: 30), header.count == 30, header.le32(0) == 0x0403_4B50 else {
            throw StoredZipError.truncated
        }
        let dataOffset = entry.localHeaderOffset + 30 + UInt64(header.le16(26)) + UInt64(header.le16(28))
        try input.seek(toOffset: dataOffset)

        let temporary = destination.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporary)
        var crc = CRC32()
        var remaining = entry.size
        do {
            while remaining > 0 {
                let chunk = try input.read(upToCount: Int(min(remaining, 4 << 20))) ?? Data()
                guard !chunk.isEmpty else { throw StoredZipError.truncated }
                crc.update(chunk)
                try output.write(contentsOf: chunk)
                remaining -= UInt64(chunk.count)
            }
            try output.close()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        guard crc.value == entry.crc32 else {
            try? FileManager.default.removeItem(at: temporary)
            throw StoredZipError.crcMismatch(entry.name)
        }
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func lastIndex(of signature: [UInt8], in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let bytes = [UInt8](data)
        for i in stride(from: bytes.count - 22, through: 0, by: -1)
        where bytes[i] == signature[0] && bytes[i + 1] == signature[1] && bytes[i + 2] == signature[2] && bytes[i + 3] == signature[3] {
            return i
        }
        return nil
    }
}

struct CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private var state: UInt32 = 0xFFFF_FFFF

    mutating func update(_ data: Data) {
        var c = state
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer { c = Self.table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        state = c
    }

    var value: UInt32 { state ^ 0xFFFF_FFFF }
}

extension Data {
    fileprivate func le16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    fileprivate func le32(_ offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
