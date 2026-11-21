import Foundation
import onnxruntime

public struct ORTError: Error, CustomStringConvertible {
    public let description: String
}

/// A thin layer over ONNX Runtime's C API: CPU sessions, tensors copied in, tensors copied out.
enum ORT {
    static let api: OrtApi = OrtGetApiBase().pointee.GetApi(UInt32(ORT_API_VERSION))!.pointee

    static let env: OpaquePointer = {
        var env: OpaquePointer?
        try! check(api.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "wao", &env))
        return env!
    }()

    static let cpu: OpaquePointer = {
        var info: OpaquePointer?
        try! check(api.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &info))
        return info!
    }()

    static func check(_ status: OpaquePointer?) throws {
        guard let status else { return }
        let message = String(cString: api.GetErrorMessage(status)!)
        api.ReleaseStatus(status)
        throw ORTError(description: message)
    }
}

/// An input tensor that owns a copy of its data for as long as ORT may read it.
final class Tensor {
    let value: OpaquePointer
    private let storage: UnsafeMutableRawPointer

    init<T>(_ data: [T], shape: [Int64], type: ONNXTensorElementDataType) throws {
        let bytes = data.count * MemoryLayout<T>.stride
        let storage = UnsafeMutableRawPointer.allocate(byteCount: max(bytes, 1), alignment: 16)
        data.withUnsafeBytes { storage.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
        var value: OpaquePointer?
        do {
            try ORT.check(ORT.api.CreateTensorWithDataAsOrtValue(ORT.cpu, storage, bytes, shape, shape.count, type, &value))
        } catch {
            storage.deallocate()
            throw error
        }
        self.storage = storage
        self.value = value!
    }

    convenience init(floats: [Float], shape: [Int64]) throws {
        try self.init(floats, shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)
    }

    convenience init(int64s: [Int64], shape: [Int64]) throws {
        try self.init(int64s, shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64)
    }

    convenience init(int32s: [Int32], shape: [Int64]) throws {
        try self.init(int32s, shape: shape, type: ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32)
    }

    deinit {
        ORT.api.ReleaseValue(value)
        storage.deallocate()
    }
}

/// An output tensor owned by ORT, read out by copying.
final class Output {
    private let value: OpaquePointer

    init(_ value: OpaquePointer) {
        self.value = value
    }

    deinit {
        ORT.api.ReleaseValue(value)
    }

    func shape() throws -> [Int64] {
        var info: OpaquePointer?
        try ORT.check(ORT.api.GetTensorTypeAndShape(value, &info))
        defer { ORT.api.ReleaseTensorTypeAndShapeInfo(info) }
        var count = 0
        try ORT.check(ORT.api.GetDimensionsCount(info, &count))
        var dims = [Int64](repeating: 0, count: count)
        try ORT.check(ORT.api.GetDimensions(info, &dims, count))
        return dims
    }

    func elements<T>(_: T.Type) throws -> [T] {
        let count = Int(try shape().reduce(1, *))
        var raw: UnsafeMutableRawPointer?
        try ORT.check(ORT.api.GetTensorMutableData(value, &raw))
        return Array(UnsafeBufferPointer(start: raw!.assumingMemoryBound(to: T.self), count: count))
    }
}

final class Session {
    private let handle: OpaquePointer

    init(path: URL, threads: Int) throws {
        var options: OpaquePointer?
        try ORT.check(ORT.api.CreateSessionOptions(&options))
        defer { ORT.api.ReleaseSessionOptions(options) }
        try ORT.check(ORT.api.SetIntraOpNumThreads(options, Int32(threads)))
        try ORT.check(ORT.api.SetInterOpNumThreads(options, 1))
        try ORT.check(ORT.api.SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL))
        var session: OpaquePointer?
        try path.path.withCString { try ORT.check(ORT.api.CreateSession(ORT.env, $0, options, &session)) }
        handle = session!
    }

    deinit {
        ORT.api.ReleaseSession(handle)
    }

    func run(_ inputs: [(String, Tensor)], outputs: [String]) throws -> [Output] {
        let inputNames = inputs.map { strdup($0.0) }
        let outputNames = outputs.map { strdup($0) }
        defer { (inputNames + outputNames).forEach { free($0) } }
        let inputValues: [OpaquePointer?] = inputs.map { $0.1.value }
        var outputValues = [OpaquePointer?](repeating: nil, count: outputs.count)
        try inputNames.map { UnsafePointer($0) }.withUnsafeBufferPointer { inNames in
            try outputNames.map { UnsafePointer($0) }.withUnsafeBufferPointer { outNames in
                try ORT.check(ORT.api.Run(
                    handle, nil, inNames.baseAddress, inputValues, inputs.count,
                    outNames.baseAddress, outputs.count, &outputValues))
            }
        }
        return outputValues.map { Output($0!) }
    }
}
