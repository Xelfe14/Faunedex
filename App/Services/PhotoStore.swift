import Foundation

/// Stores captured photos as files under Application Support and references them
/// by relative path from the SwiftData store (keeping large blobs out of the DB
/// and out of CloudKit record limits).
struct PhotoStore {
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Sightings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Persist image bytes, returning the relative filename to store on `Sighting`.
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
        try? Data(contentsOf: url(for: relativePath))
    }

    func delete(_ relativePath: String) {
        try? FileManager.default.removeItem(at: url(for: relativePath))
    }
}
