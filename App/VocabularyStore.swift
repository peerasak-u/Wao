import Foundation
import WaoCore

/// Only the container app runs the model, so the book lives in its own Application Support, not the App Group.
enum VocabularyStore {
    static let url = URL.applicationSupportDirectory.appending(path: "vocabulary.json")

    static func load() -> VocabularyBook {
        guard let data = try? Data(contentsOf: url), let book = try? JSONDecoder().decode(VocabularyBook.self, from: data)
        else { return .bundled }
        return book
    }

    static func save(_ book: VocabularyBook) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(book).write(to: url, options: .atomic)
    }
}
