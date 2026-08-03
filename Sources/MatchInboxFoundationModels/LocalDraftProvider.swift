import Foundation
import MatchInboxCore

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum LocalDraftAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var description: String {
        switch self {
        case .available: "Apple Intelligence Foundation Models are available on this Mac."
        case .unavailable(let reason): "Apple Intelligence Foundation Models are unavailable on this Mac: \(reason)"
        }
    }
}

public enum LocalDraftProvider {
    public static var availability: LocalDraftAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                return .unavailable(String(describing: reason))
            }
        }
        #endif
        return .unavailable("Apple Intelligence Foundation Models require macOS 26 or later and device availability.")
    }
}

public enum LocalReviewResult: Sendable {
    case onDevice(String)
    case deterministic([String])
    case unavailable(String)

    public var description: String {
        switch self {
        case .onDevice(let text): return text
        case .deterministic(let ideas): return ideas.joined(separator: "\n")
        case .unavailable(let reason): return "Local model unavailable: \(reason)"
        }
    }
}

public enum LocalReviewSynthesizer {
    public static func synthesize(observations: [String]) async -> LocalReviewResult {
        guard !observations.isEmpty else { return .unavailable("No approved observations.") }
        return .deterministic(deterministicLines(observations: observations))
    }

    /// Uses only the supplied, already-approved observations. It has no tools,
    /// no network fallback, and deliberately returns uncertainty instead of
    /// filling gaps with assumptions.
    public static func synthesizeOnDevice(observations: [String]) async -> LocalReviewResult {
        guard !observations.isEmpty else { return .unavailable("No approved observations.") }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = LocalDraftProvider.availability else {
                return await synthesize(observations: observations)
            }
            let session = LanguageModelSession(instructions: """
            You are a private dating-context reviewer. Use only the supplied observed text.
            Do not infer abbreviations, intentions, appearance, biography, or facts that are not explicit.
            Return three brief labelled sections: OBSERVED, POSSIBLE NEXT STEP, and UNKNOWNS.
            Every line under OBSERVED and POSSIBLE NEXT STEP must end with one supplied source ID in square brackets.
            Under POSSIBLE NEXT STEP, write only a question to consider, not an assertion or a message to send.
            Do not claim certainty.
            """)
            do {
                let numbered = numberedObservations(observations)
                let response = try await session.respond(to: "Approved visible observations:\n" + numbered.joined(separator: "\n"))
                return isGrounded(response.content, sourceIDs: numbered.indices.map { "obs-\($0 + 1)" })
                    ? .onDevice(response.content)
                    : await synthesize(observations: observations)
            } catch {
                return await synthesize(observations: observations)
            }
        }
        #endif
        return await synthesize(observations: observations)
    }

    private static func deterministicLines(observations: [String]) -> [String] {
        let nextStepIndex = observations.firstIndex { observation in
            let field = observation.lowercased()
            return field.hasPrefix("prompt_answer:") || field.hasPrefix("bio:") || field.hasPrefix("interest:")
        } ?? observations.startIndex
        return ["OBSERVED:"]
            + numberedObservations(observations).map { "- \($0)" }
            + [
                "POSSIBLE NEXT STEP:",
                "- Consider a question about one visible observation [obs-\(nextStepIndex + 1)]",
                "UNKNOWNS:",
                "- Unknowns remain unknown until explicitly imported."
            ]
    }

    private static func numberedObservations(_ observations: [String]) -> [String] {
        observations.enumerated().map { index, observation in "[obs-\(index + 1)] \(observation)" }
    }

    static func isGrounded(_ response: String, sourceIDs: [String]) -> Bool {
        let requiredSections = ["OBSERVED", "POSSIBLE NEXT STEP", "UNKNOWNS"]
        guard requiredSections.allSatisfy(response.localizedCaseInsensitiveContains) else { return false }
        let lines = response.split(whereSeparator: \.isNewline).map(String.init)
        guard
            let observedStart = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("OBSERVED") }),
            let nextStepStart = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("POSSIBLE NEXT STEP") }),
            let unknownsStart = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("UNKNOWNS") }),
            observedStart < nextStepStart,
            nextStepStart < unknownsStart
        else { return false }
        let claimLines = lines[(observedStart + 1)..<nextStepStart] + lines[(nextStepStart + 1)..<unknownsStart]
        guard !claimLines.isEmpty, claimLines.allSatisfy({ line in sourceIDs.contains(where: { line.contains("[\($0)]") }) }) else {
            return false
        }
        let citedIDs = response.split(separator: "[").compactMap { fragment -> String? in
            guard let end = fragment.firstIndex(of: "]") else { return nil }
            return String(fragment[..<end])
        }
        return !citedIDs.isEmpty && citedIDs.allSatisfy(sourceIDs.contains)
    }
}

public enum ConversationMode: String, CaseIterable, Codable, Sendable {
    case opener
    case bonding
    case keepGoing
    case closer
    case roast
    case callback
    case rephrase
    case repair
    case profilePrompt

    public var title: String {
        switch self {
        case .opener: "Openers"
        case .bonding: "Bonding ideas"
        case .keepGoing: "Keep it going"
        case .closer: "Closers"
        case .roast: "Kind roasts"
        case .callback: "Callbacks"
        case .rephrase: "Rephrase"
        case .repair: "Repair"
        case .profilePrompt: "Profile prompts"
        }
    }
}

public enum SuggestionStyle: String, CaseIterable, Codable, Sendable {
    case gentleman
    case confident
    case playful
    case romantic
    case bold
    case grounded
    case warm
    case elegant
    case witty
    case flirtatious

    public var title: String {
        switch self {
        case .gentleman: "Gentleman"
        case .confident: "Confident"
        case .playful: "Playful"
        case .romantic: "Romantic"
        case .bold: "Bold, respectful"
        case .grounded: "Grounded"
        case .warm: "Warm, expressive"
        case .elegant: "Elegant"
        case .witty: "Witty"
        case .flirtatious: "Flirtatious, respectful"
        }
    }

    public var instruction: String {
        switch self {
        case .gentleman: "warm, respectful, attentive, and never presumptuous"
        case .confident: "direct and self-assured, while leaving the other person an easy opt-out"
        case .playful: "light and witty, targeting only harmless situations or ideas"
        case .romantic: "sincere and thoughtful, without inventing intimacy"
        case .bold: "flirtatious but respectful, never sexual, manipulative, or appearance-focused"
        case .grounded: "calm, direct, self-possessed, and emotionally honest"
        case .warm: "open, expressive, attentive, and considerate without overfamiliarity"
        case .elegant: "polished, concise, thoughtful, and low-pressure"
        case .witty: "clever and lightly humorous, never sarcastic toward the person"
        case .flirtatious: "clearly interested but respectful, with no pressure or sexual framing"
        }
    }
}

public enum SocialSuggestionSafety {
    private static let prohibitedTerms = [
        "pretend to be", "lie about", "catfish", "fake vulnerability",
        "make them jealous", "love bomb", "pressure them", "coerce",
        "manipulate", "exploit their", "hide your identity", "impersonate"
    ]

    public static func isAllowed(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return !prohibitedTerms.contains { normalized.contains($0) }
    }
}

public struct LocalSuggestion: Equatable, Sendable {
    public let mode: ConversationMode
    public let text: String
    public let evidenceIDs: [String]
    public let uncertainty: String
    public let optionalOpener: String?

    public init(
        mode: ConversationMode,
        text: String,
        evidenceIDs: [String],
        uncertainty: String,
        optionalOpener: String? = nil
    ) {
        self.mode = mode
        self.text = text
        self.evidenceIDs = evidenceIDs
        self.uncertainty = uncertainty
        self.optionalOpener = optionalOpener
    }
}

public struct SuggestionEvidence: Equatable, Sendable {
    public let id: String
    public let source: String
    public let text: String

    public init(id: String, source: String, text: String) {
        self.id = id
        self.source = source
        self.text = text
    }
}

public struct ConversationSuggestionContext: Equatable, Sendable {
    public let matchProfileFacts: [String]
    public let ownerProfileFacts: [String]
    public let incomingMessages: [String]
    public let outgoingMessages: [String]

    public init(
        matchProfileFacts: [String] = [],
        ownerProfileFacts: [String] = [],
        incomingMessages: [String] = [],
        outgoingMessages: [String] = []
    ) {
        self.matchProfileFacts = matchProfileFacts
        self.ownerProfileFacts = ownerProfileFacts
        self.incomingMessages = incomingMessages
        self.outgoingMessages = outgoingMessages
    }

    public var evidence: [SuggestionEvidence] {
        var result: [SuggestionEvidence] = []
        result += incomingMessages.enumerated().map { SuggestionEvidence(id: "obs-\(result.count + $0.offset + 1)", source: "incoming message", text: $0.element) }
        result += outgoingMessages.enumerated().map { SuggestionEvidence(id: "obs-\(result.count + $0.offset + 1)", source: "outgoing message", text: $0.element) }
        result += matchProfileFacts.enumerated().map { SuggestionEvidence(id: "obs-\(result.count + $0.offset + 1)", source: "optional match context", text: $0.element) }
        result += ownerProfileFacts.enumerated().map { SuggestionEvidence(id: "obs-\(result.count + $0.offset + 1)", source: "optional owner context", text: $0.element) }
        return result
    }
}

public struct ConversationCoachingReport: Equatable, Sendable {
    public let manualMessages: Int
    public let fmInfluencedMessages: Int
    public let unclassifiedMessages: Int
    public let ideas: [String]

    public var authorshipNote: String {
        if fmInfluencedMessages == 0 && unclassifiedMessages > 0 {
            return "Machiss cannot tell which messages were manual because their authorship was not recorded."
        }
        if unclassifiedMessages > 0 {
            return "Some messages have recorded provenance; the rest cannot be classified after the fact."
        }
        return "This report uses recorded authorship only; it does not infer whether a message felt AI-written."
    }
}

public enum ConversationCoach {
    public static func review(messages: [Message]) -> ConversationCoachingReport {
        let outgoing = messages.filter { $0.direction == .outgoing }
        let manual = outgoing.filter { $0.authorship == .manual }.count
        let influenced = outgoing.filter { $0.authorship == .fmSuggested || $0.authorship == .fmEdited }.count
        let unknown = outgoing.filter { $0.authorship == .unknown }.count
        let manualTexts = outgoing.filter { $0.authorship == .manual }.map(\.text)

        var ideas: [String] = []
        if manualTexts.contains(where: { $0.split(separator: " ").count <= 3 }) {
            ideas.append("When it feels natural, add one concrete detail so the other person has something easy to pick up.")
        }
        if manualTexts.contains(where: { !$0.contains("?") }) {
            ideas.append("Try an occasional specific follow-up question instead of carrying the whole conversation with statements.")
        }
        if manualTexts.isEmpty {
            ideas.append("Mark future outgoing messages as manual when you type them so later coaching has reliable evidence.")
        } else {
            ideas.append("Keep your own wording; use suggestions as prompts, then rewrite anything that does not sound like you.")
        }
        ideas.append("Look for reciprocity: share a small detail, ask one honest question, and leave room for an easy answer.")

        return ConversationCoachingReport(
            manualMessages: manual,
            fmInfluencedMessages: influenced,
            unclassifiedMessages: unknown,
            ideas: Array(ideas.prefix(3))
        )
    }
}

public enum LocalSuggestionGenerator {
    public static func suggestions(mode: ConversationMode, context: ConversationSuggestionContext, style: SuggestionStyle = .gentleman) async -> [LocalSuggestion] {
        guard !context.evidence.isEmpty else { return [] }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = LocalDraftProvider.availability,
           let suggestion = await onDeviceSuggestion(mode: mode, style: style, context: context) {
            return [suggestion]
        }
        #endif
        return [deterministicSuggestion(mode: mode, style: style, evidence: context.evidence)]
    }

    public static func suggestions(mode: ConversationMode, observations: [String]) async -> [LocalSuggestion] {
        guard !observations.isEmpty else { return [] }
        // This compatibility overload is intentionally deterministic. Callers
        // that have typed provenance should use the context overload below to
        // opt into Foundation Models generation.
        return [deterministicSuggestion(mode: mode, evidence: observations.enumerated().map {
            SuggestionEvidence(id: "obs-\($0.offset + 1)", source: "approved observation", text: $0.element)
        })]
    }

    private static func deterministicSuggestion(mode: ConversationMode, style: SuggestionStyle = .gentleman, evidence: [SuggestionEvidence]) -> LocalSuggestion {
        let evidenceID = "obs-1"
        let fact = evidence[0].text
            .replacingOccurrences(of: "prompt_answer:", with: "")
            .replacingOccurrences(of: "visible_text:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        let opener: String?
        switch mode {
        case .opener:
            text = "Open with a curious question about “\(fact)”."
            opener = "What is the story behind “\(fact)” ?"
        case .bonding:
            text = "Ask what makes “\(fact)” meaningful, then share one small related detail about yourself."
            opener = "What does “\(fact)” look like for you?"
        case .keepGoing:
            text = "Follow the visible thread by asking for one concrete example of “\(fact)”."
            opener = "What is a recent example of that?"
        case .closer:
            text = "Close warmly by acknowledging “\(fact)” and leaving an easy thread to return to."
            opener = "I liked hearing about that—let’s pick this up soon."
        case .roast:
            text = "Playful roast: gently tease the situation around “\(fact)”, not the person."
            opener = "That is suspiciously organized—I respect it."
        case .callback:
            text = "Save “\(fact)” as a callback for a later, natural question."
            opener = "You mentioned “\(fact)” earlier—how did that turn out?"
        case .rephrase:
            text = "Rephrase your response so it acknowledges “\(fact)” and stays conversational."
            opener = "That is interesting—tell me a little more."
        case .repair:
            text = "If the exchange feels flat, return to “\(fact)” with a simple, low-pressure question."
            opener = "I may have missed the interesting part—what got you into that?"
        case .profilePrompt:
            text = "Use “\(fact)” as a profile-prompt bridge: answer briefly, then invite their version."
            opener = "I would answer that with ___. What about you?"
        }
        let stylePrefix = style == .playful && mode != .roast ? "Keep it light: " : style == .confident ? "Lead with clarity: " : ""
        return LocalSuggestion(
            mode: mode,
            text: stylePrefix + text + " [\(evidenceID)]",
            evidenceIDs: [evidenceID],
            uncertainty: "Unknowns remain unknown until explicitly imported.",
            optionalOpener: opener
        )
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable(description: "A grounded conversation idea with provenance and uncertainty.")
    struct GeneratedSuggestion {
        @Guide(description: "One concise, respectful conversation idea grounded in the supplied evidence.")
        let idea: String
        @Guide(description: "A short optional message draft. Do not claim facts not in evidence.")
        let opener: String
        @Guide(description: "Exactly one evidence ID from the supplied list, such as obs-1.")
        let evidenceID: String
        @Guide(description: "What remains unknown; never say unknown facts are true.")
        let unknowns: String
    }

    @available(macOS 26.0, *)
    private static func onDeviceSuggestion(mode: ConversationMode, style: SuggestionStyle, context: ConversationSuggestionContext) async -> LocalSuggestion? {
        let session = LanguageModelSession(instructions: """
        You generate private, local conversation suggestions. Use only the supplied observations.
        Never infer appearance, identity, age, protected traits, intentions, or biography.
        For roast mode, be kind and playful and target only a harmless situation or idea.
        Use this style: \(style.instruction).
        Return the typed suggestion schema. The evidenceID must be copied exactly from the supplied evidence.
        """)
        let evidence = context.evidence
        let numbered = evidence.map { "[\($0.id)] (\($0.source)) \($0.text)" }
        do {
            let response = try await session.respond(to: "Mode: \(mode.title)\nApproved evidence:\n" + numbered.joined(separator: "\n"), generating: GeneratedSuggestion.self)
            let generated = response.content
            guard evidence.contains(where: { $0.id == generated.evidenceID }) else { return nil }
            let combined = (generated.idea + " " + generated.opener).lowercased()
            guard !combined.contains("appearance"), !combined.contains("age"), SocialSuggestionSafety.isAllowed(combined) else { return nil }
            return LocalSuggestion(mode: mode, text: generated.idea, evidenceIDs: [generated.evidenceID], uncertainty: generated.unknowns, optionalOpener: generated.opener.isEmpty ? nil : generated.opener)
        } catch {
            return nil
        }
    }
    #endif
}
