import Testing
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
