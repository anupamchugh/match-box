import Foundation
import Testing
@testable import MatchInboxCLI
@testable import MatchInboxCore
@testable import MatchInboxSwiftData

@Test("inbox lists a reply-now thread")
func inboxListsReplyNowThread() throws {
    let file = try fixtureFile()
    let output = try MatchInboxCommand.run(arguments: ["inbox", file.path])

    #expect(output.contains("REPLY NOW: Alex"))
}

@Test("read, profile, and suggest render local-only text")
func rendersAllDraftOnlyCommands() throws {
    let file = try fixtureFile()

    #expect(try MatchInboxCommand.run(arguments: ["read", file.path, "thread-1"]).contains("THEM: How was your Sunday?"))
    #expect(try MatchInboxCommand.run(arguments: ["profile", file.path, "alex"]).contains("- Likes coffee"))
    #expect(try MatchInboxCommand.run(arguments: ["suggest", file.path, "thread-1"]).contains("How was your Sunday?"))
}

@Test("local-model suggest reports only local availability")
func localModelSuggestionDoesNotUseRemoteProvider() throws {
    let file = try fixtureFile()
    let output = try MatchInboxCommand.run(arguments: ["suggest", file.path, "thread-1", "--local-model"])

    #expect(output.contains("LOCAL MODEL:"))
    #expect(!output.lowercased().contains("api key"))
}

@Test("import saves a selected snapshot and inbox reads the saved history")
func importsAndReadsSavedHistory() throws {
    let source = try fixtureFile()
    let store = URL.temporaryDirectory.appending(path: "match-inbox-store-\(UUID().uuidString).json")

    let importOutput = try MatchInboxCommand.run(arguments: ["import", source.path, store.path])
    let inboxOutput = try MatchInboxCommand.run(arguments: ["inbox", store.path])

    #expect(importOutput.contains("IMPORTED: 1 thread"))
    #expect(inboxOutput.contains("REPLY NOW: Alex"))
}

@Test("review separates observed facts from unknowns without drafting a message")
func reviewsProfileWithoutDrafting() throws {
    let file = try fixtureFile()
    let output = try MatchInboxCommand.run(arguments: ["review", file.path, "alex"])

    #expect(output.contains("OBSERVED:"))
    #expect(output.contains("Likes coffee"))
    #expect(output.contains("UNKNOWNS:"))
    #expect(!output.contains("I noticed"))
}

@Test("Mirroir preview command writes a reviewable local capture without saving history")
func writesMirroirPreview() throws {
    let previewURL = URL.temporaryDirectory.appending(path: "match-box-mirroir-preview-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: previewURL) }

    let output = try MatchInboxCommand.run(arguments: [
        "mirroir-preview", previewURL.path(), "Chats", "Your matches (2)", "Chats (Recent)"
    ])

    let capture = try JSONDecoder().decode(ScreenCapture.self, from: Data(contentsOf: previewURL))
    #expect(output == "BRIDGED PREVIEW: bumbleChats")
    #expect(capture.kind == .bumbleChats)
}

@Test("Mirroir preview accepts a bounded explicit screen kind when OCR lacks app anchors")
func writesExplicitMirroirPreviewKind() throws {
    let previewURL = URL.temporaryDirectory.appending(path: "match-box-mirroir-thread-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: previewURL) }

    let output = try MatchInboxCommand.run(arguments: [
        "mirroir-preview", "--kind", "bumbleThread", previewURL.path(), "Delivered", "Aa"
    ])

    let capture = try JSONDecoder().decode(ScreenCapture.self, from: Data(contentsOf: previewURL))
    #expect(output == "BRIDGED PREVIEW: bumbleThread")
    #expect(capture.kind == .bumbleThread)
}

@Test("positioned Mirroir preview imports visible thread bubbles as local messages")
func writesPositionedMirroirPreview() throws {
    let directory = URL.temporaryDirectory.appending(path: "match-box-positioned-mirroir-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let observationsURL = directory.appending(path: "observations.json")
    let previewURL = directory.appending(path: "preview.json")
    let observations = [
        VisibleObservation(field: "visible_text", text: "Coffee this week?", confidence: 0.98, positionX: 0.21),
        VisibleObservation(field: "visible_text", text: "Thursday works", confidence: 0.97, positionX: 0.79),
        VisibleObservation(field: "visible_text", text: "Delivered", confidence: 0.99, positionX: 0.79),
    ]
    try JSONEncoder().encode(observations).write(to: observationsURL)

    let output = try MatchInboxCommand.run(arguments: [
        "mirroir-positioned-preview", "bumbleThread", observationsURL.path(), previewURL.path()
    ])
    let capture = try JSONDecoder().decode(ScreenCapture.self, from: Data(contentsOf: previewURL))
    let imported = try CaptureImporter.makeImport(ownerID: "owner", profileID: "bumble-sam", displayName: "Sam", capture: capture)

    #expect(output == "BRIDGED POSITIONED PREVIEW: bumbleThread")
    #expect(imported.threads.first?.messages == [
        Message(direction: .incoming, text: "Coffee this week?"),
        Message(direction: .outgoing, text: "Thursday works")
    ])
}

@Test("approved Mirroir preview uses the same local SwiftData history as the app")
func approvesMirroirPreviewIntoLocalStore() throws {
    let directory = URL.temporaryDirectory.appending(path: "match-box-bridge-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let previewURL = directory.appending(path: "preview.json")
    let storeURL = directory.appending(path: "MatchBox.store")
    let preview = MirroirBridge.makeCapture(visibleText: ["Chats", "Your matches (2)", "Chats (Recent)"], capturedAt: "2026-08-02T18:30:00Z")
    try JSONEncoder().encode(preview).write(to: previewURL)

    let output = try MatchInboxCommand.run(arguments: ["approve-mirroir-preview", previewURL.path(), storeURL.path()])

    let saved = try SwiftDataHistoryStore.persistent(at: storeURL).load(ownerID: "owner")
    #expect(output == "APPROVED PREVIEW: bumbleChats")
    #expect(saved?.profiles.first?.displayName == "Bumble inbox")
}

@Test("on-device review validates the selected local profile before model use")
func validatesOnDeviceReviewProfile() async throws {
    let file = try fixtureFile()

    await #expect(throws: MatchInboxCLIError.missingProfile("missing")) {
        try await MatchInboxCommand.runOnDeviceReview(arguments: ["review-on-device", file.path, "missing"])
    }
}

@Test("on-device review reads the same SwiftData history used by Match Box")
func reviewsPersistedLocalHistory() async throws {
    let directory = URL.temporaryDirectory.appending(path: "match-box-local-review-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appending(path: "MatchBox.store")
    let store = try SwiftDataHistoryStore.persistent(at: storeURL)
    try store.save(MatchImport(
        ownerID: "owner",
        profiles: [Profile(id: "bumble-likes", displayName: "Bumble likes", visibleFacts: ["visible_text: A fictional profile fact"])],
        threads: []
    ))

    let output = try await MatchInboxCommand.runStoredOnDeviceReview(arguments: ["review-local", storeURL.path(), "bumble-likes"])

    #expect(output.contains("OBSERVED:"))
    #expect(output.contains("[obs-1]"))
}

private func fixtureFile() throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "match-inbox-fixture-\(UUID().uuidString).json")
    try Data("""
    {"ownerID":"me","profiles":[{"id":"alex","displayName":"Alex","visibleFacts":["Likes coffee"]}],"threads":[{"id":"thread-1","participantID":"alex","messages":[{"direction":"incoming","text":"How was your Sunday?","timestamp":"2026-08-02T10:00:00Z"}]}]}
    """.utf8).write(to: url)
    return url
}
