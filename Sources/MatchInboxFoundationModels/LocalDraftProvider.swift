import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum LocalDraftAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var description: String {
        switch self {
        case .available: "Apple Foundation Models is available locally."
        case .unavailable(let reason): "Apple Foundation Models is unavailable locally: \(reason)"
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
        return .unavailable("Foundation Models requires macOS 26 or later.")
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
