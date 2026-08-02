import Foundation

public enum MatchBoxPresentation {
    public static let menuBarTitle = "Match Box"
    public static let menuBarSymbol = "heart.text.square"
}

public struct MatchImport: Codable, Equatable, Sendable {
    public let ownerID: String
    public let provenance: ImportProvenance?
    public let profiles: [Profile]
    public let threads: [Thread]

    public init(ownerID: String, provenance: ImportProvenance? = nil, profiles: [Profile], threads: [Thread]) {
        self.ownerID = ownerID
        self.provenance = provenance
        self.profiles = profiles
        self.threads = threads
    }
}

public struct ImportProvenance: Codable, Equatable, Sendable {
    public let sourceApp: String
    public let sourceScreen: String?
    public let capturedAt: String?

    public init(sourceApp: String, sourceScreen: String? = nil, capturedAt: String? = nil) {
        self.sourceApp = sourceApp
        self.sourceScreen = sourceScreen
        self.capturedAt = capturedAt
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let visibleFacts: [String]
    public let capturedKinds: [ScreenKind]
    public let subject: CaptureSubject

    public init(id: String, displayName: String, visibleFacts: [String] = []) {
        self.init(id: id, displayName: displayName, visibleFacts: visibleFacts, capturedKinds: [], subject: .legacyUnspecified)
    }

    public init(
        id: String,
        displayName: String,
        visibleFacts: [String] = [],
        capturedKinds: [ScreenKind],
        subject: CaptureSubject = .legacyUnspecified
    ) {
        self.id = id
        self.displayName = displayName
        self.visibleFacts = visibleFacts
        self.capturedKinds = capturedKinds
        self.subject = subject
    }

    private enum CodingKeys: String, CodingKey { case id, displayName, visibleFacts, capturedKinds, subject }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        visibleFacts = try values.decodeIfPresent([String].self, forKey: .visibleFacts) ?? []
        capturedKinds = try values.decodeIfPresent([ScreenKind].self, forKey: .capturedKinds) ?? []
        subject = try values.decodeIfPresent(CaptureSubject.self, forKey: .subject) ?? .legacyUnspecified
    }
}

public enum CaptureSubject: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case ownerProfile
    case matchProfile
    case likesContext
    case conversationContext
    case legacyUnspecified

    public static func inferred(for kind: ScreenKind) -> CaptureSubject? {
        switch kind {
        case .bumbleLikes, .hingeLikes:
            .likesContext
        case .bumbleChats, .hingeChats:
            .conversationContext
        case .bumbleThread, .hingeThread:
            .matchProfile
        case .bumbleProfile, .hingeProfile, .unrecognized:
            nil
        }
    }
}

public struct ProfileBrief: Equatable, Sendable {
    public let facts: [String]
    public let unknowns: [String]

    public init(facts: [String], unknowns: [String]) {
        self.facts = facts
        self.unknowns = unknowns
    }
}

public enum ProfileBriefBuilder {
    public static func build(for profile: Profile) -> ProfileBrief {
        ProfileBrief(
            facts: profile.visibleFacts,
            unknowns: ["Relationship goals are not visible."]
        )
    }
}

public struct Thread: Codable, Equatable, Sendable {
    public let id: String
    public let participantID: String
    public let messages: [Message]

    public init(id: String, participantID: String, messages: [Message]) {
        self.id = id
        self.participantID = participantID
        self.messages = messages
    }
}

public struct Message: Codable, Equatable, Hashable, Sendable {
    public let direction: MessageDirection
    public let text: String
    public let timestamp: String?

    public init(direction: MessageDirection, text: String, timestamp: String? = nil) {
        self.direction = direction
        self.text = text
        self.timestamp = timestamp
    }
}

public enum MessageDirection: String, Codable, Equatable, Hashable, Sendable {
    case incoming
    case outgoing
}

public enum ThreadPriority: Equatable, Sendable {
    case replyNow
    case wait
    case nudgeLater
}

public enum ThreadClassifier {
    public static func priority(for thread: Thread) -> ThreadPriority {
        guard let latest = thread.messages.last else { return .nudgeLater }
        return latest.direction == .incoming ? .replyNow : .wait
    }
}

public enum MatchImportValidationError: Error, Equatable {
    case unknownParticipant(String)
    case prohibitedField(String)
    case mismatchedOwner
}

public enum MatchImportValidator {
    public static func validate(_ input: MatchImport) throws {
        let profileIDs = Set(input.profiles.map(\.id))
        for thread in input.threads where !profileIDs.contains(thread.participantID) {
            throw MatchImportValidationError.unknownParticipant(thread.participantID)
        }
    }
}

public enum MatchImportDecoder {
    public static func decode(_ data: Data) throws -> MatchImport {
        try rejectProhibitedFields(in: data)
        let input = try JSONDecoder().decode(MatchImport.self, from: data)
        try MatchImportValidator.validate(input)
        return input
    }

    private static func rejectProhibitedFields(in data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let prohibited = ["send", "sendmessage", "swipe", "like", "match", "contact", "automate", "automation"]
        for key in object.keys where prohibited.contains(key.lowercased()) {
            throw MatchImportValidationError.prohibitedField(key)
        }
    }
}

public enum MatchInboxHistory {
    public static func merge(existing: MatchImport, selected: MatchImport) throws -> MatchImport {
        guard existing.ownerID == selected.ownerID else {
            throw MatchImportValidationError.mismatchedOwner
        }

        let profiles = mergeProfiles(existing: existing.profiles, selected: selected.profiles)
        let threads = mergeThreads(existing: existing.threads, selected: selected.threads)
        let merged = MatchImport(
            ownerID: existing.ownerID,
            provenance: selected.provenance ?? existing.provenance,
            profiles: profiles,
            threads: threads
        )
        try MatchImportValidator.validate(merged)
        return merged
    }

    private static func mergeProfiles(existing: [Profile], selected: [Profile]) -> [Profile] {
        var merged = existing
        for incoming in selected {
            guard let index = merged.firstIndex(where: { $0.id == incoming.id && $0.subject == incoming.subject }) else {
                merged.append(incoming)
                continue
            }
            let prior = merged[index]
            merged[index] = Profile(
                id: prior.id,
                displayName: incoming.displayName,
                visibleFacts: unique(prior.visibleFacts + incoming.visibleFacts),
                capturedKinds: unique(prior.capturedKinds + incoming.capturedKinds),
                subject: prior.subject
            )
        }
        return merged
    }

    private static func mergeThreads(existing: [Thread], selected: [Thread]) -> [Thread] {
        var merged = existing
        for incoming in selected {
            guard let index = merged.firstIndex(where: { $0.id == incoming.id }) else {
                merged.append(incoming)
                continue
            }
            let prior = merged[index]
            merged[index] = Thread(
                id: prior.id,
                participantID: incoming.participantID,
                messages: unique(prior.messages + incoming.messages)
            )
        }
        return merged
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

public struct DraftSuggestion: Equatable, Sendable {
    public let text: String
    public let source: String

    public init(text: String, source: String) {
        self.text = text
        self.source = source
    }
}

public enum DraftGenerator {
    public static func suggestions(for thread: Thread, profile: Profile) -> [DraftSuggestion] {
        let grounding: String
        if let message = thread.messages.last(where: { $0.direction == .incoming }) {
            grounding = "Message: \(message.text)"
        } else if let fact = profile.visibleFacts.first {
            grounding = "Profile fact: \(fact)"
        } else {
            grounding = "Selected conversation"
        }

        let quoted = grounding.replacingOccurrences(of: "Message: ", with: "").replacingOccurrences(of: "Profile fact: ", with: "")
        return [
            DraftSuggestion(text: "I noticed ‘\(quoted)’—tell me more.", source: grounding),
            DraftSuggestion(text: "That made me curious: what’s the story behind it?", source: grounding),
            DraftSuggestion(text: "What should I ask next about that?", source: grounding),
        ]
    }
}

public enum ScreenKind: String, Codable, Equatable, Hashable, Sendable {
    case bumbleChats
    case bumbleLikes
    case bumbleProfile
    case bumbleThread
    case hingeChats
    case hingeLikes
    case hingeProfile
    case hingeThread
    case unrecognized

    public var sourceApp: String {
        rawValue.hasPrefix("hinge") ? "hinge" : rawValue.hasPrefix("bumble") ? "bumble" : "unknown"
    }
}

public enum MatchBoxInboxSection: String, CaseIterable, Sendable {
    case chats
    case likes
    case profiles
    case review
}

public enum MatchBoxInbox {
    public static func sections(for history: MatchImport) -> [MatchBoxInboxSection] {
        MatchBoxInboxSection.allCases.filter { section in
            switch section {
            case .chats:
                !history.threads.isEmpty || history.profiles.contains { $0.capturedKinds.contains(where: isChat) }
            case .likes:
                history.profiles.contains { $0.capturedKinds.contains(where: isLike) }
            case .profiles:
                history.profiles.contains { profile in
                    profile.capturedKinds.isEmpty || profile.capturedKinds.contains(where: isProfile)
                }
            case .review:
                false
            }
        }
    }

    public static func profiles(in history: MatchImport, section: MatchBoxInboxSection) -> [Profile] {
        switch section {
        case .chats:
            return history.profiles.filter { $0.capturedKinds.contains(where: isChat) }
        case .likes:
            return history.profiles.filter { $0.capturedKinds.contains(where: isLike) }
        case .profiles:
            return history.profiles.filter { $0.capturedKinds.isEmpty || $0.capturedKinds.contains(where: isProfile) }
        case .review:
            return []
        }
    }

    private static func isChat(_ kind: ScreenKind) -> Bool {
        [.bumbleChats, .bumbleThread, .hingeChats, .hingeThread].contains(kind)
    }

    private static func isLike(_ kind: ScreenKind) -> Bool {
        [.bumbleLikes, .hingeLikes].contains(kind)
    }

    private static func isProfile(_ kind: ScreenKind) -> Bool {
        [.bumbleProfile, .hingeProfile].contains(kind)
    }
}

public struct VisibleObservation: Codable, Equatable, Sendable {
    public let field: String
    public let text: String
    public let confidence: Double
    public let positionX: Double?

    public init(field: String, text: String, confidence: Double, positionX: Double? = nil) {
        self.field = field
        self.text = text
        self.confidence = confidence
        self.positionX = positionX
    }
}

public struct ScreenCapture: Codable, Equatable, Sendable {
    public let sourceApp: String
    public let kind: ScreenKind
    public let observations: [VisibleObservation]
    public let capturedAt: String
    public init(sourceApp: String, kind: ScreenKind, observations: [VisibleObservation], capturedAt: String) { self.sourceApp = sourceApp; self.kind = kind; self.observations = observations; self.capturedAt = capturedAt }
}

/// Development-only adapter for typed observations supplied by a local Mirroir MCP host.
/// The app still presents this capture for explicit owner review before persistence.
public enum MirroirBridgeError: Error, Equatable, Sendable {
    case unrecognizedScreen
    case invalidPosition(Double)
    case prohibitedObservationField(String)
}

public enum MirroirBridge {
    public static func previewURL(applicationSupport: URL) -> URL {
        applicationSupport.appending(path: "MatchBox/MirroirBridge/preview.json")
    }

    public static func makeCapture(
        visibleText: [String],
        capturedAt: String,
        declaredKind: ScreenKind? = nil
    ) -> ScreenCapture {
        let observations = visibleText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { VisibleObservation(field: "visible_text", text: $0, confidence: 0.5) }
        let kind = declaredKind ?? ScreenClassifier.classify(visibleText: observations.map(\.text))
        return ScreenCapture(
            sourceApp: kind.sourceApp,
            kind: kind,
            observations: ProfileObservationAdapter.label(observations, for: kind),
            capturedAt: capturedAt
        )
    }

    /// Accepts local development observations that include the geometry supplied
    /// by Mirroir. The observations are still preview-only until the owner
    /// approves their import in Match Box.
    public static func makeCapture(
        observations: [VisibleObservation],
        capturedAt: String,
        declaredKind: ScreenKind
    ) throws -> ScreenCapture {
        guard declaredKind != .unrecognized else {
            throw MirroirBridgeError.unrecognizedScreen
        }
        for observation in observations {
            if let positionX = observation.positionX, !(0 ... 1).contains(positionX) {
                throw MirroirBridgeError.invalidPosition(positionX)
            }
            if prohibitedObservationFields.contains(observation.field.lowercased()) {
                throw MirroirBridgeError.prohibitedObservationField(observation.field)
            }
        }
        return ScreenCapture(
            sourceApp: declaredKind.sourceApp,
            kind: declaredKind,
            observations: ProfileObservationAdapter.label(observations, for: declaredKind),
            capturedAt: capturedAt
        )
    }

    private static let prohibitedObservationFields: Set<String> = ["action", "button", "control"]
}

/// A bounded local classifier for profile text. It labels only visible text
/// after a visible heading; all other OCR remains literal `visible_text`.
public enum ProfileObservationAdapter {
    public static func label(_ observations: [VisibleObservation], for kind: ScreenKind) -> [VisibleObservation] {
        guard [.bumbleProfile, .hingeProfile].contains(kind) else { return observations }
        var followingField: String?
        return observations.map { observation in
            guard observation.field == "visible_text" else { return observation }
            let normalized = observation.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if promptQuestionHeadings.contains(normalized) || normalized.contains("together we could") || normalized.contains("the way to win me over") {
                followingField = "prompt_answer"
                return relabel(observation, field: "prompt_question")
            }
            if interestHeadings.contains(normalized) {
                followingField = "interest"
                return observation
            }
            if bioHeadings.contains(normalized) {
                followingField = "bio"
                return observation
            }
            guard let followingField, !isMetadata(normalized) else { return observation }
            return relabel(observation, field: followingField)
        }
    }

    private static let promptQuestionHeadings: Set<String> = ["i'm looking for", "i am looking for", "my simple pleasures", "my real-life superpower"]
    private static let interestHeadings: Set<String> = ["my interests", "interests"]
    private static let bioHeadings: Set<String> = ["about me", "my bio"]

    private static func isMetadata(_ text: String) -> Bool {
        text.contains("photo verified") || text.rangeOfCharacter(from: .decimalDigits) != nil && text.count <= 8
    }

    private static func relabel(_ observation: VisibleObservation, field: String) -> VisibleObservation {
        VisibleObservation(field: field, text: observation.text, confidence: observation.confidence, positionX: observation.positionX)
    }
}

public struct CaptureIdentity: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// Extracts only a short visible name-like token. When OCR does not expose one,
    /// it deliberately uses a neutral label instead of guessing a person’s identity.
    public static func make(sourceApp: String, observations: [VisibleObservation]) -> CaptureIdentity {
        make(sourceApp: sourceApp, kind: .unrecognized, observations: observations)
    }

    public static func make(sourceApp: String, kind: ScreenKind, observations: [VisibleObservation]) -> CaptureIdentity {
        let app = sourceApp.lowercased().filter { $0.isLetter || $0.isNumber }
        switch kind {
        case .bumbleChats, .hingeChats:
            return CaptureIdentity(id: "\(app)-inbox", displayName: "\(sourceApp.capitalized) inbox")
        case .bumbleLikes, .hingeLikes:
            return CaptureIdentity(id: "\(app)-likes", displayName: "\(sourceApp.capitalized) likes")
        default:
            break
        }
        let rawToken = observations
            .map(\.text)
            .flatMap { $0.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " }) }
            .map(String.init)
            .first { value in
                let trimmed = value.trimmingCharacters(in: .punctuationCharacters)
                return trimmed.count >= 1 && trimmed.count <= 32 && trimmed.rangeOfCharacter(from: .letters) != nil
            }
        let token = rawToken?.trimmingCharacters(in: .punctuationCharacters)

        let displayName = token?.isEmpty == false ? token! : "Captured profile"
        let normalized = displayName.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let compact = normalized.split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return CaptureIdentity(id: "\(app)-\(compact.isEmpty ? "profile" : compact)", displayName: displayName)
    }
}

public enum ScreenClassifier {
    public static func classify(visibleText: [String]) -> ScreenKind {
        let text = visibleText.joined(separator: " ").lowercased()
        if text.contains("hinge") || text.contains("standouts") || text.contains("roses") {
            if text.contains("likes you") || text.contains("standouts") { return .hingeLikes }
            if text.contains("your turn") || text.contains("matches") { return .hingeChats }
            if text.contains("together we could") || text.contains("the way to win me over") { return .hingeProfile }
            if text.contains("message") { return .hingeThread }
        }
        if text.contains("liked you") { return .bumbleLikes }
        if text.contains("your matches") && text.contains("chats") { return .bumbleChats }
        if text.contains("write a note to") || text.contains("photo verified") { return .bumbleProfile }
        if text.contains("message") && text.contains("typing") { return .bumbleThread }
        return .unrecognized
    }
}

public enum CaptureImportError: Error, Equatable {
    case unsupportedScreen(ScreenKind)
    case subjectRequired(ScreenKind)
}

public enum ConversationExtractor {
    public static func messages(from observations: [VisibleObservation]) -> [Message] {
        observations.compactMap { observation in
            guard let positionX = observation.positionX, !isConversationChrome(observation.text) else { return nil }
            return Message(direction: positionX >= 0.5 ? .outgoing : .incoming, text: observation.text)
        }
    }

    private static func isConversationChrome(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || ["delivered", "read", "aa", "+"].contains(normalized)
    }
}

public enum CaptureImporter {
    public static func makeImport(
        ownerID: String,
        profileID: String,
        displayName: String,
        capture: ScreenCapture,
        subject: CaptureSubject? = nil
    ) throws -> MatchImport {
        guard capture.kind != .unrecognized else {
            throw CaptureImportError.unsupportedScreen(capture.kind)
        }
        guard let subject = subject ?? CaptureSubject.inferred(for: capture.kind) else {
            throw CaptureImportError.subjectRequired(capture.kind)
        }
        let facts = capture.observations.map { "\($0.field): \($0.text)" }
        let messages = capture.kind == .bumbleThread || capture.kind == .hingeThread
            ? ConversationExtractor.messages(from: capture.observations)
            : []
        let threads = messages.isEmpty
            ? []
            : [Thread(id: "\(profileID)-thread", participantID: profileID, messages: messages)]
        return MatchImport(
            ownerID: ownerID,
            provenance: ImportProvenance(sourceApp: capture.sourceApp, sourceScreen: capture.kind.rawValue, capturedAt: capture.capturedAt),
            profiles: [Profile(id: profileID, displayName: displayName, visibleFacts: facts, capturedKinds: [capture.kind], subject: subject)],
            threads: threads
        )
    }
}
