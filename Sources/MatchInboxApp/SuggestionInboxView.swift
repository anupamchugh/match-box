import AppKit
import SwiftUI
import MatchInboxCore
import MatchInboxFoundationModels

struct SuggestionInboxView: View {
    let history: MatchImport?
    let selectedThreadID: String?
    let showsHeader: Bool
    @State private var mode: ConversationMode = .bonding
    @State private var style: SuggestionStyle = .gentleman
    @State private var suggestions: [LocalSuggestion] = []
    @State private var isGenerating = false

    init(history: MatchImport?, selectedThreadID: String? = nil, showsHeader: Bool = true) {
        self.history = history
        self.selectedThreadID = selectedThreadID
        self.showsHeader = showsHeader
    }

    private var context: ConversationSuggestionContext {
        guard let history else { return ConversationSuggestionContext() }
        let matchFacts = history.profiles
            .filter { $0.subject == .matchProfile || $0.subject == .legacyUnspecified }
            .flatMap(\.visibleFacts)
        let ownerFacts = history.profiles
            .filter { $0.subject == .ownerProfile }
            .flatMap(\.visibleFacts)
        let messages = history.threads
            .filter { selectedThreadID == nil || $0.id == selectedThreadID }
            .flatMap(\.messages)
            .suffix(8)
        return ConversationSuggestionContext(
            matchProfileFacts: matchFacts,
            ownerProfileFacts: ownerFacts,
            incomingMessages: messages.filter { $0.direction == .incoming }.map(\.text),
            outgoingMessages: messages.filter { $0.direction == .outgoing }.map(\.text)
        )
    }

    private var evidence: [SuggestionEvidence] {
        context.evidence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Suggestions Inbox")
                        .font(.largeTitle.bold())
                    Text("Find a thoughtful next thread from approved local context.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("On this Mac", systemImage: "lock.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(MatchBoxCopy.theConversation, systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)
                    if context.incomingMessages.isEmpty && context.outgoingMessages.isEmpty {
                        Text("No approved messages in this conversation yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ideas start from these messages. Profile context is optional and shown separately.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach((context.incomingMessages.map { ("Incoming", $0) } + context.outgoingMessages.map { ("Outgoing", $0) }).suffix(4), id: \.1) { label, message in
                            Label { Text("\(label): \(message)").textSelection(.enabled) } icon: {
                                Image(systemName: label == "Incoming" ? "arrow.down.left" : "arrow.up.right")
                            }
                            .font(.callout)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Optional context about you", systemImage: "person.crop.circle")
                        .font(.headline)
                    if context.ownerProfileFacts.isEmpty {
                        Text("No approved facts about you are in this workspace yet.")
                            .foregroundStyle(.secondary)
                        Text("Use Capture context → My profile to add a small, explicit set of your own prompts or interests.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("These facts can help you find an authentic bridge. They are not treated as messages you already sent.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(context.ownerProfileFacts.prefix(3), id: \.self) { fact in
                            Label(fact, systemImage: "checkmark.circle")
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(ConversationMode.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .frame(width: 190)
                Picker("Voice", selection: $style) {
                    ForEach(SuggestionStyle.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .frame(width: 170)
                Button(isGenerating ? "Thinking…" : "Generate ideas") {
                    Task { await generate() }
                }
                .disabled(isGenerating || evidence.isEmpty)
                Spacer()
                Text("Private on-device ideas")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 330, alignment: .trailing)
            }

            if evidence.isEmpty {
                ContentUnavailableView(
                    "No approved context yet",
                    systemImage: "sparkles",
                    description: Text("Capture a Bumble, Hinge, or other supported visible screen with Mirroir, review it, and save the local observations first.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isGenerating {
                ProgressView("Generating from approved observations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if suggestions.isEmpty {
                ContentUnavailableView(
                    "No ideas yet",
                    systemImage: "lightbulb",
                    description: Text("Choose a mode and generate a local suggestion.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                            SuggestionCard(suggestion: suggestion, evidence: evidence)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
        .task { await generate() }
        .onChange(of: mode) { _, _ in
            Task { await generate() }
        }
        .onChange(of: style) { _, _ in
            Task { await generate() }
        }
    }

    private func generate() async {
        guard !evidence.isEmpty else {
            suggestions = []
            return
        }
        isGenerating = true
        suggestions = await LocalSuggestionGenerator.suggestions(mode: mode, context: context, style: style)
        isGenerating = false
    }
}

private struct SuggestionCard: View {
    let suggestion: LocalSuggestion
    let evidence: [SuggestionEvidence]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(suggestion.mode.title, systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("Local suggestion")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(suggestion.text)
                .font(.title3)
                .textSelection(.enabled)
            if let opener = suggestion.optionalOpener {
                GroupBox("Optional opener") {
                    HStack(alignment: .top) {
                        Text(opener).textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(opener, forType: .string)
                        }
                    }
                }
            }
            Divider()
            Text(MatchBoxCopy.basedOnWhatYouShared)
                .font(.subheadline.weight(.semibold))
            ForEach(suggestion.evidenceIDs, id: \.self) { evidenceID in
                if let item = evidence.first(where: { $0.id == evidenceID }) {
                    Label("\(friendlySource(item.source)): \"\(item.text)\"", systemImage: "quote.opening")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Label("\(MatchBoxCopy.whatMayBeMissingText): \(suggestion.uncertainty)", systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func friendlySource(_ source: String) -> String {
        switch source {
        case "incoming message": return MatchBoxCopy.theirMessageText
        case "outgoing message": return MatchBoxCopy.yourMessageText
        case "optional match context": return MatchBoxCopy.optionalProfileDetailText
        case "optional owner context": return MatchBoxCopy.yourOptionalContextText
        default: return MatchBoxCopy.whatYouSharedText
        }
    }
}
