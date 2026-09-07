import Foundation

/// Anything the app stores on disk goes through here.
///
/// Deliberately not `UserDefaults`: career points, house rules and an
/// in-progress match are real user progress. They deserve atomic writes and a
/// version they can be migrated from, and `UserDefaults` gives neither (§12).
protocol Persisting: Sendable {
    func load<T: Decodable>(_ type: T.Type, from key: StorageKey) throws -> T?
    func save<T: Encodable>(_ value: T, to key: StorageKey) throws
    func remove(_ key: StorageKey) throws
}

/// A named document in Application Support.
struct StorageKey: Hashable, Sendable {
    let filename: String

    static let careerProfile = StorageKey(filename: "career-profile.json")
    static let settings = StorageKey(filename: "settings.json")
    static let houseRules = StorageKey(filename: "house-rules.json")
    static let matchInProgress = StorageKey(filename: "match-in-progress.json")
}

/// Everything persisted carries a schema version from day one, and the
/// migration switch exists even while there is only one version — adding it
/// later means guessing what unversioned files contained.
struct VersionedDocument<Payload: Codable & Sendable>: Codable, Sendable {
    static var currentVersion: Int { 1 }

    var schemaVersion: Int
    var payload: Payload

    init(_ payload: Payload) {
        schemaVersion = Self.currentVersion
        self.payload = payload
    }
}

enum PersistenceError: Error, Equatable {
    /// The file was written by a newer build than this one.
    case unsupportedSchemaVersion(found: Int, supported: Int)
}

/// Atomic JSON files in Application Support.
struct FilePersistence: Persisting {
    private let directory: URL

    // `FileManager` is not `Sendable`, and `Persisting` is, so this type holds
    // only the URL and reaches for `FileManager.default` — which is documented
    // thread-safe — at each call site.
    init(directoryName: String = "Spades") throws {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for key: StorageKey) -> URL {
        directory.appendingPathComponent(key.filename, isDirectory: false)
    }

    func load<T: Decodable>(_ type: T.Type, from key: StorageKey) throws -> T? {
        let url = url(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to key: StorageKey) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        // .atomic writes to a temporary file and renames, so a crash mid-write
        // leaves the previous save intact rather than a truncated one.
        try data.write(to: url(for: key), options: [.atomic])
    }

    func remove(_ key: StorageKey) throws {
        let url = url(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

extension Persisting {
    /// Loads a versioned document, running the migration switch.
    func loadVersioned<Payload: Codable & Sendable>(
        _ type: Payload.Type,
        from key: StorageKey
    ) throws -> Payload? {
        guard let document = try load(VersionedDocument<Payload>.self, from: key) else { return nil }
        return try migrate(document)
    }

    func saveVersioned<Payload: Codable & Sendable>(_ payload: Payload, to key: StorageKey) throws {
        try save(VersionedDocument(payload), to: key)
    }

    private func migrate<Payload: Codable & Sendable>(
        _ document: VersionedDocument<Payload>
    ) throws -> Payload {
        switch document.schemaVersion {
        case VersionedDocument<Payload>.currentVersion:
            return document.payload
        case let version where version > VersionedDocument<Payload>.currentVersion:
            // A downgrade. Refuse rather than silently discarding fields we
            // cannot see, which would quietly delete the player's progress.
            throw PersistenceError.unsupportedSchemaVersion(
                found: version,
                supported: VersionedDocument<Payload>.currentVersion
            )
        default:
            // No older versions exist yet. When one does, its upgrade goes here.
            return document.payload
        }
    }
}

/// In-memory storage for tests and previews.
final class MemoryPersistence: Persisting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StorageKey: Data] = [:]

    init() {}

    func load<T: Decodable>(_ type: T.Type, from key: StorageKey) throws -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = storage[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to key: StorageKey) throws {
        let data = try JSONEncoder().encode(value)
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    func remove(_ key: StorageKey) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = nil
    }
}
