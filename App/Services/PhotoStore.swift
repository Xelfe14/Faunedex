import Foundation

/// Stores images as files under Application Support and references them by
/// relative path from the SwiftData store, keeping large blobs out of the
/// database and out of CloudKit's record size limits.
///
/// One instance per kind of image. Sightings and recipe photos live in separate
/// folders so neither can collide with or delete the other's files.
struct PhotoStore {
    private let directory: URL

    init(folder: String = "Sightings") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Persist image bytes, returning the relative filename to store on a model.
    @discardableResult
    func save(_ data: Data, id: UUID, ext: String = "jpg") throws -> String {
        let name = "\(id.uuidString).\(ext)"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    func url(for relativePath: String) -> URL {
        directory.appendingPathComponent(relativePath)
    }

    func load(_ relativePath: String) -> Data? {
        guard !relativePath.isEmpty else { return nil }
        return try? Data(contentsOf: url(for: relativePath))
    }

    func delete(_ relativePath: String) {
        guard !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }
}
