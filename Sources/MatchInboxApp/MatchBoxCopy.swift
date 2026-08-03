import SwiftUI

/// Stable consumer-facing vocabulary for the Mac app.
///
/// Technical provenance names stay in MatchInboxFoundationModels. Views use
/// this namespace so product language can be reviewed and localized in one
/// place without changing model instructions or stored data.
@MainActor
enum MatchBoxCopy {
    static let theConversation: LocalizedStringKey = "The conversation"
    static let conversationStart: LocalizedStringKey = "These messages are the starting point for ideas. Optional profile context appears below."
    static let optionalProfileContext: LocalizedStringKey = "Optional profile context"
    static let noOptionalProfileContext: LocalizedStringKey = "No optional profile context saved yet."
    static let optionalProfileExplanation: LocalizedStringKey = "Profile context is optional. The conversation above comes first."
    static let whyThisIdea: LocalizedStringKey = "Why this idea"
    static let theirMessage: LocalizedStringKey = "Their message"
    static let yourMessage: LocalizedStringKey = "Your message"
    static let optionalProfileDetail: LocalizedStringKey = "Optional profile detail"
    static let yourOptionalContext: LocalizedStringKey = "Your optional context"
    static let whatYouShared: LocalizedStringKey = "What you shared"

    // Dynamic labels are assembled into a sentence, so keep their plain
    // values separate from the LocalizedStringKey values used by SwiftUI.
    static let theirMessageText = "Their message"
    static let yourMessageText = "Your message"
    static let optionalProfileDetailText = "Optional profile detail"
    static let yourOptionalContextText = "Your optional context"
    static let whatYouSharedText = "What you shared"
}
