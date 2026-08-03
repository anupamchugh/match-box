import Testing
import MatchInboxCore
@testable import MatchInboxFoundationModels

@Test("local Foundation Models reports availability without a remote fallback")
func reportsLocalAvailabilityOnly() {
    #expect(!LocalDraftProvider.availability.description.isEmpty)
}

@Test("local review synthesis never exposes a cloud provider")
func localReviewSynthesisIsBounded() async {
    let result = await LocalReviewSynthesizer.synthesize(observations: ["intent: Open to seeing where things go"])
    #expect(!result.description.lowercased().contains("openai"))
    #expect(!result.description.lowercased().contains("claude"))
}

@Test("deterministic local review cites each approved observation")
func deterministicReviewCitesSources() async {
    let result = await LocalReviewSynthesizer.synthesize(observations: [
        "prompt: Likes comfort movies",
        "message: CB"
    ])

    #expect(result.description.contains("[obs-1] prompt: Likes comfort movies"))
    #expect(result.description.contains("[obs-2] message: CB"))
    #expect(result.description.contains("UNKNOWNS:"))
}

@Test("deterministic review prefers a visible prompt answer over identity metadata")
func deterministicReviewPrefersPromptContent() async {
    let result = await LocalReviewSynthesizer.synthesize(observations: [
        "visible_text: A, 32",
        "prompt_answer: A fictional prompt answer",
        "interest: Art"
    ])

    #expect(result.description.contains("POSSIBLE NEXT STEP:\n- Consider a question about one visible observation [obs-2]"))
}

@Test("rejects an on-device next step that lacks a source citation")
func rejectsUngroundedOnDeviceNextStep() {
    let response = """
    OBSERVED:
    [obs-1] visible_text: A visible fact
    POSSIBLE NEXT STEP:
    What is the story behind it?
    UNKNOWNS:
    None.
    """

    #expect(!LocalReviewSynthesizer.isGrounded(response, sourceIDs: ["obs-1"]))
}

@Test("conversation toolbox exposes the approved local modes")
func conversationToolboxExposesModes() {
    #expect(Set(ConversationMode.allCases) == Set([
        .opener, .bonding, .keepGoing, .closer, .roast,
        .callback, .rephrase, .repair, .profilePrompt
    ]))
}

@Test("deterministic bonding ideas cite visible evidence and preserve unknowns")
func deterministicBondingIdeasCiteEvidence() async {
    let ideas = await LocalSuggestionGenerator.suggestions(
        mode: .bonding,
        observations: ["prompt_answer: Fictional productive weekend plans"]
    )

    #expect(ideas.count == 1)
    #expect(ideas[0].evidenceIDs == ["obs-1"])
    #expect(ideas[0].uncertainty.contains("Unknowns remain unknown"))
    #expect(ideas[0].text.contains("productive"))
}

@Test("roast mode stays kind and avoids sensitive targeting")
func roastModeStaysKind() async {
    let ideas = await LocalSuggestionGenerator.suggestions(
        mode: .roast,
        observations: ["prompt_answer: I alphabetize my bookshelf"]
    )

    #expect(ideas[0].text.lowercased().contains("playful"))
    #expect(!ideas[0].text.lowercased().contains("appearance"))
    #expect(!ideas[0].text.lowercased().contains("age"))
}

@Test("typed suggestion context keeps profile and message direction separate")
func typedSuggestionContextPreservesProvenance() {
    let context = ConversationSuggestionContext(
        matchProfileFacts: ["Gardening"],
        ownerProfileFacts: ["Likes cooking"],
        incomingMessages: ["Hey there"],
        outgoingMessages: ["I made vegetable curry"]
    )

    #expect(context.matchProfileFacts == ["Gardening"])
    #expect(context.incomingMessages == ["Hey there"])
    #expect(context.outgoingMessages == ["I made vegetable curry"])
    #expect(context.evidence.map(\.text) == ["Hey there", "I made vegetable curry", "Gardening", "Likes cooking"])
    #expect(context.evidence.first?.source == "incoming message")
    #expect(context.evidence.filter { $0.source == "optional match context" }.map(\.text) == ["Gardening"])
}

@Test("suggestion styles stay respectful and distinct")
func suggestionStylesStayRespectful() {
    #expect(SuggestionStyle.allCases.contains(.gentleman))
    #expect(SuggestionStyle.bold.instruction.contains("respectful"))
    #expect(SuggestionStyle.bold.instruction.contains("never sexual"))
}

@Test("social suggestion safety rejects deception and coercion")
func socialSuggestionSafetyRejectsDeception() {
    #expect(SocialSuggestionSafety.isAllowed("Ask a sincere question about her routine."))
    #expect(!SocialSuggestionSafety.isAllowed("Make them jealous and pretend to be someone else."))
    #expect(!SocialSuggestionSafety.isAllowed("Pressure them until they reply."))
}

@Test("conversation coaching reports only recorded authorship")
func conversationCoachingUsesRecordedAuthorship() {
    let report = ConversationCoach.review(messages: [
        Message(direction: .incoming, text: "What are you cooking?"),
        Message(direction: .outgoing, text: "Curry tonight", authorship: .manual),
        Message(direction: .outgoing, text: "Tell me more", authorship: .fmEdited),
        Message(direction: .outgoing, text: "Nice", authorship: .unknown)
    ])

    #expect(report.manualMessages == 1)
    #expect(report.fmInfluencedMessages == 1)
    #expect(report.unclassifiedMessages == 1)
    #expect(report.authorshipNote.contains("recorded provenance"))
    #expect(!report.ideas.isEmpty)
}
