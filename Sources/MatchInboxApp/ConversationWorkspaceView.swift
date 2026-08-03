import SwiftUI
import MatchInboxCore
import MatchInboxFoundationModels

struct ConversationWorkspaceView: View {
    let history: MatchImport
    @State private var selectedThreadID: String?

    private var threadGroups: [[MatchInboxCore.Thread]] {
        var groups: [[MatchInboxCore.Thread]] = []
        for thread in history.threads {
            if let index = groups.firstIndex(where: { duplicateKey($0[0]) == duplicateKey(thread) }) {
                groups[index].append(thread)
            } else {
                groups.append([thread])
            }
        }
        return groups
    }

    private var visibleThreads: [MatchInboxCore.Thread] {
        threadGroups.compactMap(\.first)
    }

    private var selectedThread: MatchInboxCore.Thread? {
        history.threads.first { $0.id == selectedThreadID } ?? visibleThreads.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            threadList.frame(width: 230)
            Divider()
            if let thread = selectedThread {
                conversationDetail(thread: thread)
            } else {
                ContentUnavailableView("No conversations yet", systemImage: "bubble.left.and.bubble.right", description: Text("Capture and approve a visible Bumble or Hinge thread to see it here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(minWidth: 960, maxWidth: 1180, minHeight: 680, maxHeight: .infinity, alignment: .topLeading)
        .task { selectedThreadID = selectedThreadID ?? history.threads.first?.id }
    }

    private var threadList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your conversations").font(.title2.bold())
            Text("Start with the person who needs a thoughtful reply.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleThreads, id: \.id) { thread in
                        ThreadInboxRow(
                            thread: thread,
                            displayName: displayName(for: thread),
                            captureNames: captureNames(for: thread),
                            duplicateCount: threadGroups.first(where: { $0.contains(where: { $0.id == thread.id }) })?.count ?? 1,
                            profile: profile(for: thread),
                            isSelected: thread.id == (selectedThread?.id ?? selectedThreadID)
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedThreadID = thread.id }
                    }
                }
            }
        }
    }

    private func conversationDetail(thread: MatchInboxCore.Thread) -> some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: thread)).font(.largeTitle.bold())
                    HStack(spacing: 8) {
                        Text(sourceLabel(for: thread)); Text("•")
                        Text(ThreadClassifier.priority(for: thread).workspaceLabel)
                            .foregroundStyle(ThreadClassifier.priority(for: thread) == .replyNow ? .orange : .secondary)
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Label("On this Mac", systemImage: "lock.fill")
                    .font(.callout.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            if let group = threadGroups.first(where: { $0.contains(where: { $0.id == thread.id }) }), group.count > 1 {
                Label("Confirm this conversation: these saved captures have the same visible messages (\(captureNames(for: thread))). Ideas are paused until you confirm who this is.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ConversationMessagesView(messages: thread.messages)
            ProfileSummaryView(profile: profile(for: thread))
            SuggestionInboxView(history: isAmbiguous(thread) ? nil : history, selectedThreadID: thread.id, showsHeader: false)
            DisclosureGroup("Improve your conversation") {
                ConversationCoachingView(messages: thread.messages)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func profile(for thread: MatchInboxCore.Thread) -> Profile? {
        history.profiles.first { $0.id == thread.participantID && $0.subject == .matchProfile }
            ?? history.profiles.first { $0.id == thread.participantID }
    }

    private func displayName(for thread: MatchInboxCore.Thread) -> String {
        if isAmbiguous(thread) { return "Confirm identity" }
        return captureNames(for: thread).isEmpty ? "Conversation" : captureNames(for: thread)
    }

    private func captureNames(for thread: MatchInboxCore.Thread) -> String {
        let names = threadGroups
            .first(where: { $0.contains(where: { $0.id == thread.id }) })?
            .compactMap { profile(for: $0)?.displayName }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) { result.append(name) }
            } ?? []
        return names.joined(separator: ", ")
    }

    private func isAmbiguous(_ thread: MatchInboxCore.Thread) -> Bool {
        (threadGroups.first(where: { $0.contains(where: { $0.id == thread.id }) })?.count ?? 1) > 1
    }

    private func duplicateKey(_ thread: MatchInboxCore.Thread) -> String {
        thread.messages.map { "\($0.direction.rawValue):\($0.text)" }.joined(separator: "\u{1F}" )
    }

    private func sourceLabel(for thread: MatchInboxCore.Thread) -> String {
        guard let kind = profile(for: thread)?.capturedKinds.first else { return "Saved thread" }
        return kind.sourceApp.capitalized
    }
}

private struct ConversationMessagesView: View {
    let messages: [Message]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(MatchBoxCopy.theConversation, systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Text(MatchBoxCopy.conversationStart)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            HStack {
                                if message.direction == .outgoing { Spacer(minLength: 45) }
                                VStack(alignment: message.direction == .incoming ? .leading : .trailing, spacing: 3) {
                                    Text(message.direction == .incoming ? "Incoming" : "Outgoing")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(message.text)
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(message.direction == .incoming ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                                if message.direction == .incoming { Spacer(minLength: 45) }
                            }
                        }
                    }
                }
                .frame(minHeight: 150, maxHeight: 360)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProfileSummaryView: View {
    let profile: Profile?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(MatchBoxCopy.optionalProfileContext, systemImage: "person.crop.circle")
                    .font(.headline)
                if let profile, !profile.visibleFacts.isEmpty {
                    ForEach(profile.visibleFacts, id: \.self) { fact in
                        Text(fact.replacingOccurrences(of: "visible_text: ", with: ""))
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(MatchBoxCopy.noOptionalProfileContext)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(MatchBoxCopy.optionalProfileExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ConversationCoachingView: View {
    let messages: [Message]

    private var report: ConversationCoachingReport {
        ConversationCoach.review(messages: messages)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Conversation coaching", systemImage: "graduationcap")
                        .font(.headline)
                    Spacer()
                    Text("Local review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(report.authorshipNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("Manual: \(report.manualMessages)")
                    Text("FM-influenced: \(report.fmInfluencedMessages)")
                    Text("Unknown: \(report.unclassifiedMessages)")
                }
                .font(.caption.weight(.medium))
                ForEach(report.ideas, id: \.self) { idea in
                    Label(idea, systemImage: "lightbulb")
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ThreadInboxRow: View {
    let thread: MatchInboxCore.Thread
    let displayName: String
    let captureNames: String
    let duplicateCount: Int
    let profile: Profile?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(displayName).font(.headline).lineLimit(1)
                Spacer()
                if ThreadClassifier.priority(for: thread) == .replyNow { Circle().fill(.orange).frame(width: 7, height: 7) }
            }
            if duplicateCount > 1 {
                Label("\(duplicateCount) captures", systemImage: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if !captureNames.isEmpty {
                    Text(captureNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(thread.messages.last?.text ?? "No visible message").font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Text(ThreadClassifier.priority(for: thread).workspaceLabel).font(.caption).foregroundStyle(.secondary)
        }
        .padding(11)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension ThreadPriority {
    var workspaceLabel: String {
        switch self {
        case .replyNow: "Reply now"
        case .wait: "Waiting"
        case .nudgeLater: "Nudge later"
        }
    }
}
