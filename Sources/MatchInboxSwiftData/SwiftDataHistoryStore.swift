import Foundation
import SwiftData
import MatchInboxCore

@Model
public final class StoredMatchHistory {
    @Attribute(.unique) public var ownerID: String
    public var payload: Data

    public init(ownerID: String, payload: Data) {
        self.ownerID = ownerID
        self.payload = payload
    }
}

public final class SwiftDataHistoryStore {
    private let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
    }

    public static func inMemory() throws -> SwiftDataHistoryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try SwiftDataHistoryStore(container: ModelContainer(for: StoredMatchHistory.self, configurations: configuration))
    }

    public static func persistent() throws -> SwiftDataHistoryStore {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(path: "MatchBox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try persistent(at: directory.appending(path: "MatchBox.store"))
    }

    public static func persistent(at url: URL) throws -> SwiftDataHistoryStore {
        let configuration = ModelConfiguration("MatchBox", url: url, cloudKitDatabase: .none)
        return try SwiftDataHistoryStore(container: ModelContainer(for: StoredMatchHistory.self, configurations: configuration))
    }

    public func save(_ snapshot: MatchImport) throws {
        let context = ModelContext(container)
        let ownerID = snapshot.ownerID
        let descriptor = FetchDescriptor<StoredMatchHistory>(predicate: #Predicate { $0.ownerID == ownerID })
        let data = try JSONEncoder().encode(snapshot)
        if let existing = try context.fetch(descriptor).first {
            existing.payload = data
        } else {
            context.insert(StoredMatchHistory(ownerID: ownerID, payload: data))
        }
        try context.save()
    }

    public func load(ownerID: String) throws -> MatchImport? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<StoredMatchHistory>(predicate: #Predicate { $0.ownerID == ownerID })
        guard let history = try context.fetch(descriptor).first else { return nil }
        return try MatchImportDecoder.decode(history.payload)
    }

    public func clear(ownerID: String) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<StoredMatchHistory>(predicate: #Predicate { $0.ownerID == ownerID })
        for record in try context.fetch(descriptor) {
            context.delete(record)
        }
        try context.save()
    }
}
