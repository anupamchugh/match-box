import Foundation
import MatchInboxCore
import MatchInboxFoundationModels
import MatchInboxSwiftData

public enum MatchInboxCLIError: Error, Equatable {
    case usage
    case missingThread(String)
    case missingProfile(String)
}

public enum MatchInboxCommand {
    public static func runOnDeviceReview(arguments: [String]) async throws -> String {
        guard arguments.count == 3 else { throw MatchInboxCLIError.usage }
        let input = try MatchImportDecoder.decode(Data(contentsOf: URL(filePath: arguments[1])))
        guard let profile = input.profiles.first(where: { $0.id == arguments[2] }) else {
            throw MatchInboxCLIError.missingProfile(arguments[2])
        }
        return await renderOnDeviceReview(profile: profile)
    }

    /// Reviews the approved SwiftData history used by the Match Box app.
    /// This is intentionally a local-store command rather than treating SQLite
    /// bytes as an import snapshot.
    public static func runStoredOnDeviceReview(arguments: [String]) async throws -> String {
        guard arguments.count == 3 else { throw MatchInboxCLIError.usage }
        let store = try SwiftDataHistoryStore.persistent(at: URL(filePath: arguments[1]))
        guard let history = try store.load(ownerID: "owner") else { throw MatchInboxCLIError.missingProfile(arguments[2]) }
        guard let profile = history.profiles.first(where: { $0.id == arguments[2] }) else {
            throw MatchInboxCLIError.missingProfile(arguments[2])
        }
        return await renderOnDeviceReview(profile: profile)
    }

    private static func renderOnDeviceReview(profile: Profile) async -> String {
        let result = await LocalReviewSynthesizer.synthesizeOnDevice(observations: profile.visibleFacts)
        switch result {
        case .onDevice(let text):
            return "ON-DEVICE REVIEW:\n\(text)"
        case .deterministic(let lines):
            return "LOCAL FALLBACK REVIEW:\n\(lines.joined(separator: "\n"))"
        case .unavailable(let reason):
            return "LOCAL MODEL UNAVAILABLE: \(reason)"
        }
    }

    public static func run(arguments: [String]) throws -> String {
        guard arguments.count >= 2 else { throw MatchInboxCLIError.usage }
        let command = arguments[0]

        if command == "import" {
            return try importSnapshot(arguments: arguments)
        }
        if command == "mirroir-preview" {
            return try writeMirroirPreview(arguments: arguments)
        }
        if command == "mirroir-positioned-preview" {
            return try writePositionedMirroirPreview(arguments: arguments)
        }
        if command == "approve-mirroir-preview" {
            return try approveMirroirPreview(arguments: arguments)
        }

        let input = try MatchImportDecoder.decode(Data(contentsOf: URL(filePath: arguments[1])))

        switch command {
        case "inbox":
            return inbox(input)
        case "read":
            guard arguments.count == 3 else { throw MatchInboxCLIError.usage }
            return try read(input, threadID: arguments[2])
        case "profile":
            guard arguments.count == 3 else { throw MatchInboxCLIError.usage }
            return try profile(input, profileID: arguments[2])
        case "review":
            guard arguments.count == 3 else { throw MatchInboxCLIError.usage }
            return try review(input, profileID: arguments[2])
        case "suggest":
            guard arguments.count == 3 || (arguments.count == 4 && arguments.last == "--local-model") else { throw MatchInboxCLIError.usage }
            let drafts = try suggest(input, threadID: arguments[2])
            guard arguments.count == 4 else { return drafts }
            return "LOCAL MODEL: \(LocalDraftProvider.availability.description)\nDETERMINISTIC DRAFTS:\n\(drafts)"
        default:
            throw MatchInboxCLIError.usage
        }
    }

    private static func importSnapshot(arguments: [String]) throws -> String {
        guard arguments.count == 3 else { throw MatchInboxCLIError.usage }
        let selected = try MatchImportDecoder.decode(Data(contentsOf: URL(filePath: arguments[1])))
        let store = URL(filePath: arguments[2])
        let history: MatchImport
        if FileManager.default.fileExists(atPath: store.path()) {
            let existing = try MatchImportDecoder.decode(Data(contentsOf: store))
            history = try MatchInboxHistory.merge(existing: existing, selected: selected)
        } else {
            history = selected
        }
        let data = try JSONEncoder().encode(history)
        try data.write(to: store, options: .atomic)
        return "IMPORTED: \(selected.threads.count) thread\(selected.threads.count == 1 ? "" : "s") into local history"
    }

    private static func writeMirroirPreview(arguments: [String]) throws -> String {
        let destination: URL
        let visibleText: [String]
        let declaredKind: ScreenKind?
        if arguments.dropFirst().first == "--kind" {
            guard arguments.count >= 5, let kind = ScreenKind(rawValue: arguments[2]) else { throw MatchInboxCLIError.usage }
            destination = URL(filePath: arguments[3])
            visibleText = Array(arguments.dropFirst(4))
            declaredKind = kind
        } else {
            guard arguments.count >= 3 else { throw MatchInboxCLIError.usage }
            destination = URL(filePath: arguments[1])
            visibleText = Array(arguments.dropFirst(2))
            declaredKind = nil
        }
        let capture = MirroirBridge.makeCapture(
            visibleText: visibleText,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            declaredKind: declaredKind
        )
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(capture).write(to: destination, options: .atomic)
        return "BRIDGED PREVIEW: \(capture.kind.rawValue)"
    }

    private static func writePositionedMirroirPreview(arguments: [String]) throws -> String {
        guard arguments.count == 4, let kind = ScreenKind(rawValue: arguments[1]) else {
            throw MatchInboxCLIError.usage
        }
        let observations = try JSONDecoder().decode(
            [VisibleObservation].self,
            from: Data(contentsOf: URL(filePath: arguments[2]))
        )
        let capture = try MirroirBridge.makeCapture(
            observations: observations,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            declaredKind: kind
        )
        let destination = URL(filePath: arguments[3])
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(capture).write(to: destination, options: .atomic)
        return "BRIDGED POSITIONED PREVIEW: \(capture.kind.rawValue)"
    }

    private static func approveMirroirPreview(arguments: [String]) throws -> String {
        guard arguments.count == 3 || arguments.count == 4 else { throw MatchInboxCLIError.usage }
        let capture = try JSONDecoder().decode(ScreenCapture.self, from: Data(contentsOf: URL(filePath: arguments[1])))
        let identity = CaptureIdentity.make(sourceApp: capture.sourceApp, kind: capture.kind, observations: capture.observations)
        let subject = arguments.count == 4 ? CaptureSubject(rawValue: arguments[3]) : nil
        let incoming = try CaptureImporter.makeImport(
            ownerID: "owner",
            profileID: identity.id,
            displayName: identity.displayName,
            capture: capture,
            subject: subject
        )
        let store = try SwiftDataHistoryStore.persistent(at: URL(filePath: arguments[2]))
        let merged = try store.load(ownerID: "owner").map { try MatchInboxHistory.merge(existing: $0, selected: incoming) } ?? incoming
        try store.save(merged)
        return "APPROVED PREVIEW: \(capture.kind.rawValue)"
    }

    private static func inbox(_ input: MatchImport) -> String {
        input.threads.compactMap { thread in
            guard let profile = input.profiles.first(where: { $0.id == thread.participantID }) else { return nil }
            let label: String
            switch ThreadClassifier.priority(for: thread) {
            case .replyNow: label = "REPLY NOW"
            case .wait: label = "WAIT"
            case .nudgeLater: label = "NUDGE LATER"
            }
            return "\(label): \(profile.displayName) [\(thread.id)]"
        }.joined(separator: "\n")
    }

    private static func read(_ input: MatchImport, threadID: String) throws -> String {
        guard let thread = input.threads.first(where: { $0.id == threadID }) else { throw MatchInboxCLIError.missingThread(threadID) }
        return thread.messages.map { message in
            "\(message.direction == .incoming ? "THEM" : "YOU"): \(message.text)"
        }.joined(separator: "\n")
    }

    private static func profile(_ input: MatchImport, profileID: String) throws -> String {
        guard let profile = input.profiles.first(where: { $0.id == profileID }) else { throw MatchInboxCLIError.missingProfile(profileID) }
        let brief = ProfileBriefBuilder.build(for: profile)
        return (["PROFILE: \(profile.displayName)", "VISIBLE FACTS:"] + brief.facts.map { "- \($0)" } + ["UNKNOWNS:"] + brief.unknowns.map { "- \($0)" }).joined(separator: "\n")
    }

    private static func review(_ input: MatchImport, profileID: String) throws -> String {
        guard let profile = input.profiles.first(where: { $0.id == profileID }) else { throw MatchInboxCLIError.missingProfile(profileID) }
        let brief = ProfileBriefBuilder.build(for: profile)
        return (["REVIEW: \(profile.displayName)", "OBSERVED:"]
            + brief.facts.map { "- \($0)" }
            + ["DECISION: CONSIDER", "- Decide whether these visible facts align with your preferences.", "UNKNOWNS:"]
            + brief.unknowns.map { "- \($0)" })
            .joined(separator: "\n")
    }

    private static func suggest(_ input: MatchImport, threadID: String) throws -> String {
        guard let thread = input.threads.first(where: { $0.id == threadID }) else { throw MatchInboxCLIError.missingThread(threadID) }
        guard let profile = input.profiles.first(where: { $0.id == thread.participantID }) else {
            throw MatchInboxCLIError.missingProfile(thread.participantID)
        }
        return DraftGenerator.suggestions(for: thread, profile: profile).enumerated().map { index, suggestion in
            "\(index + 1). \(suggestion.text)\n   SOURCE: \(suggestion.source)"
        }.joined(separator: "\n")
    }
}
