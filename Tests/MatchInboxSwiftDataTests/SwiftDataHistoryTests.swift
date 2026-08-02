import Foundation
import Testing
@testable import MatchInboxCore
@testable import MatchInboxSwiftData

@Suite(.serialized)
struct SwiftDataHistoryTests {

@Test("SwiftData keeps selected history locally")
func storesSelectedHistory() throws {
    let store = try SwiftDataHistoryStore.inMemory()
    let snapshot = MatchImport(
        ownerID: "me",
        profiles: [Profile(id: "alex", displayName: "Alex", visibleFacts: ["Likes films"])],
        threads: [Thread(id: "thread-1", participantID: "alex", messages: [])]
    )

    try store.save(snapshot)

    #expect(try store.load(ownerID: "me") == snapshot)
}

}

@Test("SwiftData persists history in a dedicated caller-selected store")
func persistsHistoryAtDedicatedStoreURL() throws {
    let directory = URL.temporaryDirectory.appending(path: "match-box-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SwiftDataHistoryStore.persistent(at: directory.appending(path: "MatchBox.store"))
    let snapshot = MatchImport(ownerID: "me", profiles: [Profile(id: "context", displayName: "Bumble inbox")], threads: [])

    try store.save(snapshot)

    #expect(try store.load(ownerID: "me") == snapshot)
}
