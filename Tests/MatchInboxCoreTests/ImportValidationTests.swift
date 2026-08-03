import Foundation
import Testing
@testable import MatchInboxCore

@Test("decodes a manual redacted import")
func decodesManualImport() throws {
    let data = Data("""
    {
      "ownerID": "me",
      "profiles": [{"id": "alex", "displayName": "Alex", "visibleFacts": ["Likes coffee"]}],
      "threads": [{"id": "thread-1", "participantID": "alex", "messages": [{"direction": "incoming", "text": "Hi", "timestamp": "2026-08-02T10:00:00Z"}]}]
    }
    """.utf8)

    let input = try MatchImportDecoder.decode(data)

    #expect(input.profiles.first?.displayName == "Alex")
    #expect(input.threads.first?.messages.first?.timestamp == "2026-08-02T10:00:00Z")
}

@Test("rejects action fields in an import")
func rejectsAutomationField() throws {
    let data = Data("""
    {"ownerID":"me","sendMessage":"nope","profiles":[],"threads":[]}
    """.utf8)

    #expect(throws: MatchImportValidationError.prohibitedField("sendMessage")) {
        try MatchImportDecoder.decode(data)
    }
}

@Test("rejects a thread whose participant is absent from profiles")
func rejectsUnknownParticipant() throws {
    let input = MatchImport(
        ownerID: "me",
        profiles: [Profile(id: "me", displayName: "Owner")],
        threads: [Thread(id: "thread-1", participantID: "unknown", messages: [])]
    )

    #expect(throws: MatchImportValidationError.unknownParticipant("unknown")) {
        try MatchImportValidator.validate(input)
    }
}

@Test("marks a thread with a new incoming message as reply now")
func classifiesIncomingMessageAsReplyNow() {
    let thread = Thread(
        id: "thread-1",
        participantID: "alex",
        messages: [Message(direction: .incoming, text: "How was your day?")]
    )

    #expect(ThreadClassifier.priority(for: thread) == .replyNow)
}

@Test("capture diff identifies only newly visible lines")
func captureDiffIdentifiesNewVisibleLines() {
    let prior = MatchImport(
        ownerID: "me",
        provenance: ImportProvenance(sourceApp: "bumble", sourceScreen: "bumbleThread", capturedAt: "2026-08-03T10:00:00Z"),
        profiles: [Profile(id: "alex", displayName: "Alex", visibleFacts: ["visible_text: Hi"])],
        threads: []
    )
    let capture = ScreenCapture(
        sourceApp: "bumble",
        kind: .bumbleThread,
        observations: [
            VisibleObservation(field: "visible_text", text: "Hi", confidence: 0.9),
            VisibleObservation(field: "visible_text", text: "How was your day?", confidence: 0.9)
        ],
        capturedAt: "2026-08-03T10:05:00Z"
    )

    let diff = CaptureDiff.compare(capture: capture, history: prior)

    #expect(diff.isFresh)
    #expect(diff.newVisibleText == ["How was your day?"])
    #expect(diff.previousCaptureAt == "2026-08-03T10:00:00Z")
}

@Test("profile brief keeps visible facts separate from unknown context")
func buildsProfileBrief() {
    let profile = Profile(
        id: "alex",
        displayName: "Alex",
        visibleFacts: ["Likes coffee", "Works in design"]
    )

    let brief = ProfileBriefBuilder.build(for: profile)

    #expect(brief.facts == ["Likes coffee", "Works in design"])
    #expect(brief.unknowns == ["Relationship goals are not visible."])
}

@Test("merges a selected snapshot into local history without duplicating messages")
func mergesSelectedSnapshotIntoHistory() throws {
    let existing = MatchImport(
        ownerID: "me",
        profiles: [Profile(id: "alex", displayName: "Alex", visibleFacts: ["Likes coffee"])],
        threads: [Thread(id: "thread-1", participantID: "alex", messages: [
            Message(direction: .incoming, text: "Hi", timestamp: "2026-08-02T10:00:00Z")
        ])]
    )
    let selected = MatchImport(
        ownerID: "me",
        profiles: [Profile(id: "alex", displayName: "Alex", visibleFacts: ["Likes coffee", "Enjoys films"])],
        threads: [Thread(id: "thread-1", participantID: "alex", messages: [
            Message(direction: .incoming, text: "Hi", timestamp: "2026-08-02T10:00:00Z"),
            Message(direction: .outgoing, text: "What is your comfort movie?", timestamp: "2026-08-02T10:01:00Z")
        ])]
    )

    let merged = try MatchInboxHistory.merge(existing: existing, selected: selected)

    #expect(merged.profiles.first?.visibleFacts == ["Likes coffee", "Enjoys films"])
    #expect(merged.threads.first?.messages.map(\.text) == ["Hi", "What is your comfort movie?"])
}

@Test("keeps an owner profile and match profile separate when visible names collide")
func keepsDistinctSubjectsSeparateDuringMerge() throws {
    let existing = MatchImport(
        ownerID: "me",
        profiles: [Profile(id: "bumble-s", displayName: "S", visibleFacts: ["Owner prompt"], capturedKinds: [.bumbleProfile], subject: .ownerProfile)],
        threads: []
    )
    let selected = MatchImport(
        ownerID: "me",
        profiles: [Profile(id: "bumble-s", displayName: "S", visibleFacts: ["Match prompt"], capturedKinds: [.bumbleProfile], subject: .matchProfile)],
        threads: []
    )

    let merged = try MatchInboxHistory.merge(existing: existing, selected: selected)

    #expect(merged.profiles.count == 2)
    #expect(Set(merged.profiles.map(\.subject)) == [.ownerProfile, .matchProfile])
}

@Test("grounds a draft in a visible profile fact when a thread has no incoming message")
func groundsDraftInProfileFact() {
    let profile = Profile(id: "alex", displayName: "Alex", visibleFacts: ["Likes comfort movies"])
    let thread = Thread(id: "thread-1", participantID: "alex", messages: [])

    let suggestions = DraftGenerator.suggestions(for: thread, profile: profile)

    #expect(suggestions.first?.source == "Profile fact: Likes comfort movies")
    #expect(suggestions.first?.text.contains("comfort movies") == true)
}

@Test("classifies a Bumble liked-you capture from visible anchors")
func classifiesBumbleLikesScreen() {
    #expect(ScreenClassifier.classify(visibleText: ["Liked You", "They're into you!"]) == .bumbleLikes)
}

@Test("classifies Hinge likes without treating it as Bumble")
func classifiesHingeLikesScreen() {
    let kind = ScreenClassifier.classify(visibleText: ["Hinge", "Likes You", "Standouts", "Roses"])
    #expect(kind == .hingeLikes)
    #expect(kind.sourceApp == "hinge")
}

@Test("capture keeps visible observations and confidence as typed data")
func capturesVisibleObservations() {
    let capture = ScreenCapture(
        sourceApp: "bumble",
        kind: .bumbleLikes,
        observations: [VisibleObservation(field: "intent", text: "Open to seeing where things go", confidence: 0.92)],
        capturedAt: "2026-08-02T17:40:00Z"
    )
    #expect(capture.observations.first?.field == "intent")
    #expect(capture.observations.first?.confidence == 0.92)
}

@Test("turns a Bumble likes capture into a preview-only import")
func importsBumbleLikeCapture() throws {
    let capture = ScreenCapture(sourceApp: "bumble", kind: .bumbleLikes, observations: [VisibleObservation(field: "intent", text: "Open to seeing where things go", confidence: 0.92)], capturedAt: "2026-08-02T17:40:00Z")
    let imported = try CaptureImporter.makeImport(ownerID: "me", profileID: "bumble-1", displayName: "S", capture: capture)
    #expect(imported.provenance?.sourceScreen == "bumbleLikes")
    #expect(imported.profiles.first?.visibleFacts == ["intent: Open to seeing where things go"])
}

@Test("requires an explicit subject before importing an ambiguous profile screen")
func rejectsUnlabelledProfileCapture() {
    let capture = ScreenCapture(
        sourceApp: "bumble",
        kind: .bumbleProfile,
        observations: [VisibleObservation(field: "visible_text", text: "A profile prompt", confidence: 0.92)],
        capturedAt: "2026-08-03T00:30:00Z"
    )

    #expect(throws: CaptureImportError.self) {
        try CaptureImporter.makeImport(ownerID: "me", profileID: "bumble-sam", displayName: "Sam", capture: capture)
    }
}

@Test("derives a stable local profile identity without inventing a name")
func derivesCaptureIdentity() {
    let identity = CaptureIdentity.make(
        sourceApp: "Bumble",
        observations: [
            VisibleObservation(field: "visible_text", text: "S, 29", confidence: 0.95),
            VisibleObservation(field: "visible_text", text: "Likes comfort movies", confidence: 0.93)
        ]
    )

    #expect(identity.displayName == "S")
    #expect(identity.id == "bumble-s")
}

@Test("thread identity prefers a visible header observation by vertical position")
func prefersHeaderObservationByVerticalPosition() {
    let identity = CaptureIdentity.make(
        sourceApp: "bumble",
        kind: .bumbleThread,
        observations: [
            VisibleObservation(field: "visible_text", text: "Your Opening Move", confidence: 0.99, positionY: 0.78),
            VisibleObservation(field: "visible_text", text: "B", confidence: 0.99, positionY: 0.87),
            VisibleObservation(field: "visible_text", text: "Fictional productive weekend plans", confidence: 0.99, positionY: 0.64)
        ]
    )

    #expect(identity.displayName == "B")
}

@Test("identity extraction skips conversation chrome before the visible header")
func skipsConversationChromeWhenDerivingIdentity() {
    let identity = CaptureIdentity.make(
        sourceApp: "bumble",
        kind: .bumbleThread,
        observations: [
            VisibleObservation(field: "visible_text", text: "24", confidence: 0.99),
            VisibleObservation(field: "visible_text", text: "11:32", confidence: 0.99),
            VisibleObservation(field: "visible_text", text: "Your Opening Move", confidence: 0.99),
            VisibleObservation(field: "visible_text", text: "B", confidence: 0.99),
            VisibleObservation(field: "visible_text", text: "What does your perfect weekend look like?", confidence: 0.99)
        ]
    )

    #expect(identity.displayName == "B")
    #expect(identity.id == "bumble-b")
}

@Test("uses source context rather than inventing a person from an inbox heading")
func derivesInboxContextIdentity() {
    let identity = CaptureIdentity.make(
        sourceApp: "bumble",
        kind: .bumbleChats,
        observations: [VisibleObservation(field: "visible_text", text: "Chats", confidence: 0.99)]
    )

    #expect(identity.id == "bumble-inbox")
    #expect(identity.displayName == "Bumble inbox")
}

@Test("imports a selected chat-list capture as visible local context")
func importsBumbleChatsCapture() throws {
    let capture = ScreenCapture(
        sourceApp: "bumble",
        kind: .bumbleChats,
        observations: [VisibleObservation(field: "visible_text", text: "Your matches", confidence: 0.98)],
        capturedAt: "2026-08-02T17:40:00Z"
    )

    let imported = try CaptureImporter.makeImport(ownerID: "me", profileID: "bumble-context", displayName: "Bumble context", capture: capture)

    #expect(imported.profiles.first?.visibleFacts == ["visible_text: Your matches"])
}

@Test("retains the captured screen kind so the local inbox can separate context")
func retainsCapturedScreenKind() throws {
    let capture = ScreenCapture(
        sourceApp: "bumble",
        kind: .bumbleLikes,
        observations: [VisibleObservation(field: "visible_text", text: "Liked You", confidence: 0.99)],
        capturedAt: "2026-08-02T18:00:00Z"
    )

    let imported = try CaptureImporter.makeImport(ownerID: "me", profileID: "bumble-likes", displayName: "Bumble likes", capture: capture)

    #expect(imported.profiles.first?.capturedKinds == [.bumbleLikes])
    #expect(MatchBoxInbox.sections(for: imported) == [.suggestions, .likes])
}

@Test("turns a Mirroir development observation into the same reviewable capture type")
func importsMirroirDevelopmentObservation() {
    let capture = MirroirBridge.makeCapture(
        visibleText: ["Chats", "Your matches (2)", "Chats (Recent)"],
        capturedAt: "2026-08-02T18:30:00Z"
    )

    #expect(capture.kind == .bumbleChats)
    #expect(capture.sourceApp == "bumble")
    #expect(capture.observations.allSatisfy { $0.field == "visible_text" })
}

@Test("uses a dedicated local development bridge location")
func usesDedicatedMirroirBridgeLocation() {
    let applicationSupport = URL(filePath: "/tmp/Application Support")
    let url = MirroirBridge.previewURL(applicationSupport: applicationSupport)

    #expect(url.path(percentEncoded: false) == "/tmp/Application Support/MatchBox/MirroirBridge/preview.json")
}

@Test("classifies every supported Bumble and Hinge bridge screen")
func classifiesSupportedMirroirBridgeScreens() {
    let fixtures: [([String], ScreenKind)] = [
        (["Chats", "Your matches (2)", "Chats (Recent)"], .bumbleChats),
        (["Liked You", "They’re into you!"], .bumbleLikes),
        (["Photo Verified", "Write a note to Sam"], .bumbleProfile),
        (["Message", "Typing…"], .bumbleThread),
        (["Hinge", "Your Turn", "Matches"], .hingeChats),
        (["Hinge", "Likes You", "Roses"], .hingeLikes),
        (["Hinge", "Together we could"], .hingeProfile),
        (["Hinge", "Message"], .hingeThread),
    ]

    for (visibleText, expectedKind) in fixtures {
        #expect(MirroirBridge.makeCapture(visibleText: visibleText, capturedAt: "2026-08-02T19:00:00Z").kind == expectedKind)
    }
}

@Test("accepts an explicit bounded app screen kind from a development MCP host")
func acceptsExplicitMirroirScreenKind() {
    let capture = MirroirBridge.makeCapture(
        visibleText: ["Delivered", "Aa"],
        capturedAt: "2026-08-02T19:10:00Z",
        declaredKind: .bumbleThread
    )

    #expect(capture.kind == .bumbleThread)
    #expect(capture.sourceApp == "bumble")
}

@Test("labels visible Bumble profile prompts and interests before local import")
func labelsBumbleProfileObservations() {
    let capture = MirroirBridge.makeCapture(
        visibleText: [
            "A, 32",
            "I'm looking for",
            "A long-term relationship",
            "My interests",
            "Art",
            "Cafe-hopping"
        ],
        capturedAt: "2026-08-03T01:30:00Z",
        declaredKind: .bumbleProfile
    )

    #expect(capture.observations.map(\.field) == [
        "visible_text",
        "prompt_question",
        "prompt_answer",
        "visible_text",
        "interest",
        "interest"
    ])
}

@Test("turns positioned Mirroir thread observations into direction-aware messages")
func importsPositionedMirroirThreadObservations() throws {
    let capture = try MirroirBridge.makeCapture(
        observations: [
            VisibleObservation(field: "visible_text", text: "Coffee this week?", confidence: 0.98, positionX: 0.21),
            VisibleObservation(field: "visible_text", text: "Thursday works", confidence: 0.97, positionX: 0.79),
            VisibleObservation(field: "visible_text", text: "Delivered", confidence: 0.99, positionX: 0.79),
        ],
        capturedAt: "2026-08-03T00:20:00Z",
        declaredKind: .bumbleThread
    )

    let imported = try CaptureImporter.makeImport(
        ownerID: "me",
        profileID: "bumble-sam",
        displayName: "Sam",
        capture: capture
    )

    #expect(imported.threads.first?.messages == [
        Message(direction: .incoming, text: "Coffee this week?"),
        Message(direction: .outgoing, text: "Thursday works")
    ])
}

@Test("rejects unrecognized Mirroir screens and out-of-bounds geometry")
func rejectsInvalidMirroirPositionedObservations() {
    #expect(throws: MirroirBridgeError.unrecognizedScreen) {
        try MirroirBridge.makeCapture(
            observations: [],
            capturedAt: "2026-08-03T00:20:00Z",
            declaredKind: .unrecognized
        )
    }
    #expect(throws: MirroirBridgeError.invalidPosition(1.01)) {
        try MirroirBridge.makeCapture(
            observations: [VisibleObservation(field: "visible_text", text: "Visible message", confidence: 0.98, positionX: 1.01)],
            capturedAt: "2026-08-03T00:20:00Z",
            declaredKind: .bumbleThread
        )
    }
    #expect(throws: MirroirBridgeError.prohibitedObservationField("button")) {
        try MirroirBridge.makeCapture(
            observations: [VisibleObservation(field: "button", text: "Send", confidence: 0.98, positionX: 0.79)],
            capturedAt: "2026-08-03T00:20:00Z",
            declaredKind: .bumbleThread
        )
    }
}

@Test("imports positioned conversation bubbles as direction-aware local messages")
func importsPositionedConversationBubbles() throws {
    let capture = ScreenCapture(
        sourceApp: "bumble",
        kind: .bumbleThread,
        observations: [
            VisibleObservation(field: "visible_text", text: "Want coffee?", confidence: 0.98, positionX: 0.22),
            VisibleObservation(field: "visible_text", text: "Thursday works", confidence: 0.97, positionX: 0.78),
            VisibleObservation(field: "visible_text", text: "Delivered", confidence: 0.99, positionX: 0.80),
        ],
        capturedAt: "2026-08-03T00:10:00Z"
    )

    let imported = try CaptureImporter.makeImport(ownerID: "me", profileID: "bumble-sam", displayName: "Sam", capture: capture)

    #expect(imported.threads.first?.messages == [
        Message(direction: .incoming, text: "Want coffee?"),
        Message(direction: .outgoing, text: "Thursday works")
    ])
}

@Test("exposes a concise menu-bar label for the local companion")
func exposesMenuBarLabel() {
    #expect(MatchBoxPresentation.menuBarTitle == "Machiss")
    #expect(MatchBoxPresentation.menuBarSymbol == "heart.text.square")
}
