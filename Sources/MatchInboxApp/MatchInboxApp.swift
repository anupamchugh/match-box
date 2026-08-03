import AppKit
import SwiftUI
import MatchInboxCore
import MatchInboxFoundationModels
import MatchInboxSwiftData
import OSLog

@main
struct MatchInboxApp: App {
    var body: some Scene {
        WindowGroup("Machiss") {
            MatchInboxWorkspace()
        }
        .defaultSize(width: 1180, height: 760)
        .defaultWindowPlacement { _, context in
            let visible = context.defaultDisplay.visibleRect
            let width = min(1180, max(960, visible.width * 0.88))
            let height = min(760, max(640, visible.height * 0.82))
            return WindowPlacement(size: CGSize(width: width, height: height))
        }
        MenuBarExtra(MatchBoxPresentation.menuBarTitle, systemImage: MatchBoxPresentation.menuBarSymbol) {
            Button("Open Machiss") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Machiss" })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Quit Machiss") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct MatchInboxWorkspace: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var captureService = WindowCaptureService()
    @State private var history: MatchImport?
    @State private var saveError: String?
    @State private var review: String?
    @State private var isReviewing = false
    @State private var saveStatus: String?
    @State private var showingClearHistoryConfirmation = false
    @State private var selection: MatchBoxInboxSection? = .suggestions
    private let ownerID = "owner"
    private let logger = Logger(subsystem: "com.anupamchugh.matchinbox", category: "history")

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Workspace") {
                    ForEach(MatchBoxInboxSection.allCases, id: \.self) { section in
                        Label {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text("\(count(for: section))").foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: section.symbol)
                        }
                        .tag(section)
                    }
                }
                Section("Private by design") {
                    Label("On this Mac", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            if (selection == .suggestions || selection == .chats), let history {
                ConversationWorkspaceView(history: history)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Machiss").font(.largeTitle.bold())
                            Text("A calmer next move for your conversations.")
                                .font(.title3).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("On this Mac", systemImage: "lock.fill")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                    }
                    Text("Read a visible conversation, keep it on this Mac, and decide what sounds like you.")
                        .foregroundStyle(.secondary)

                    if history == nil && captureService.capture == nil {
                        OnboardingGuide(onStart: { selection = .review })
                    }

                    capturePanel

                    if let capture = captureService.capture {
                        CapturePreview(capture: capture, history: history, onApprove: approve)
                        if saveStatus == nil {
                            Label("Preview only — not saved yet", systemImage: "eye")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }

                    if selection == .review, let history {
                        modelReviewPanel(history: history)
                    } else {
                        ContextTable(section: selection ?? .chats, history: history)
                    }

                    Label("Suggestions stay on this Mac", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selection = .review
                } label: {
                    Label("Capture context", systemImage: "viewfinder")
                }
                .help("Read a visible conversation or profile on this Mac")
                .accessibilityIdentifier("capture-context")
            }
            ToolbarItem {
                Button {
                    loadHistory()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload approved conversations from this Mac")
                .accessibilityIdentifier("refresh-history")
            }
            ToolbarItem {
                Button {
                    showingClearHistoryConfirmation = true
                } label: {
                    Label("Clear local history", systemImage: "trash")
                }
                .help("Delete approved Machiss history from this Mac")
                .accessibilityIdentifier("clear-local-history")
                .disabled(history == nil)
            }
        }
        .confirmationDialog("Clear all Machiss history from this Mac?", isPresented: $showingClearHistoryConfirmation, titleVisibility: .visible) {
            Button("Clear local history", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes approved local context. It does not change Bumble or Hinge.")
        }
        .task { loadHistory() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadHistory() }
        }
    }

    private func count(for section: MatchBoxInboxSection) -> Int {
        guard let history else { return 0 }
        switch section {
        case .chats:
            let fingerprints = Set(history.threads.map { thread in
                thread.messages.map { "\($0.direction.rawValue):\($0.text)" }.joined(separator: "\u{1F}")
            })
            return fingerprints.count
        case .likes, .profiles:
            return MatchBoxInbox.profiles(in: history, section: section).count
        case .review:
            return history.profiles.isEmpty ? 0 : 1
        case .suggestions:
            return history.profiles.isEmpty && history.threads.isEmpty ? 0 : 1
        }
    }

    private func modelReviewPanel(history: MatchImport) -> some View {
        GroupBox("On-device review") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional. It receives only the locally saved visible facts and never sends a message or changes a dating app.")
                    .foregroundStyle(.secondary)
                Button(isReviewing ? "Reviewing…" : "Review saved context") {
                    Task {
                        isReviewing = true
                        let observations = history.profiles.flatMap(\.visibleFacts)
                        review = await LocalReviewSynthesizer.synthesizeOnDevice(observations: observations).description
                        isReviewing = false
                    }
                }
                .disabled(isReviewing)
                if let review {
                    Text(review).textSelection(.enabled).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capturePanel: some View {
        GroupBox("Bring in a conversation") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open a conversation in iPhone Mirroring, then let Machiss read only what is visible. Nothing is sent, and screenshots are not retained.")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await captureService.captureIPhoneMirroring() }
                } label: {
                    Label(captureService.isCapturing ? "Reading visible screen…" : "Read visible screen", systemImage: "viewfinder")
                }
                .disabled(captureService.isCapturing)
                .accessibilityIdentifier("read-visible-screen")
                DisclosureGroup("Developer tools") {
                    Button {
                        captureService.importMirroirDevelopmentPreview()
                    } label: {
                        Label("Import Mirroir test preview", systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(captureService.isCapturing)
                    Text("Development only. Still requires review before saving.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = captureService.errorMessage ?? saveError {
                    Text(error).foregroundStyle(.red)
                }
                if let saveStatus {
                    Label(saveStatus, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func approve(_ capture: ScreenCapture, subject: CaptureSubject) {
        do {
            let identity = CaptureIdentity.make(sourceApp: capture.sourceApp, kind: capture.kind, observations: capture.observations)
            let incoming = try CaptureImporter.makeImport(
                ownerID: ownerID,
                profileID: identity.id,
                displayName: identity.displayName,
                capture: capture,
                subject: subject
            )
            let store = try SwiftDataHistoryStore.persistent()
            let merged = try store.load(ownerID: ownerID).map { try MatchInboxHistory.merge(existing: $0, selected: incoming) } ?? incoming
            try store.save(merged)
            history = merged
            saveError = nil
            saveStatus = "Saved locally — \(incoming.profiles.count) context record"
            logger.notice("Saved context kind=\(capture.kind.rawValue, privacy: .public) profiles=\(incoming.profiles.count, privacy: .public)")
        } catch {
            saveError = error.localizedDescription
            saveStatus = nil
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadHistory() {
        do {
            history = try SwiftDataHistoryStore.persistent().load(ownerID: ownerID)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearHistory() {
        do {
            try SwiftDataHistoryStore.persistent().clear(ownerID: ownerID)
            history = nil
            saveStatus = "Local history cleared"
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct OnboardingGuide: View {
    let onStart: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("A private three-step workflow", systemImage: "sparkles")
                    .font(.headline)
                Text("Machiss helps you think; you stay in control.")
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 12) {
                    OnboardingStep(number: "1", title: "Choose", detail: "Show one visible conversation on your Mac.")
                    OnboardingStep(number: "2", title: "Review", detail: "Check the words before anything is saved.")
                    OnboardingStep(number: "3", title: "Decide", detail: "Consider a local idea; nothing is sent for you.")
                }
                Button("Choose a visible conversation") { onStart() }
                    .accessibilityIdentifier("start-capture")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Machiss private three-step workflow")
    }
}

private struct OnboardingStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.16), in: Circle())
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CapturePreview: View {
    let capture: ScreenCapture
    let history: MatchImport?
    let onApprove: (ScreenCapture, CaptureSubject) -> Void
    @State private var selectedProfileSubject: CaptureSubject?

    init(capture: ScreenCapture, history: MatchImport?, onApprove: @escaping (ScreenCapture, CaptureSubject) -> Void) {
        self.capture = capture
        self.history = history
        self.onApprove = onApprove
        _selectedProfileSubject = State(initialValue: nil)
    }

    private var subject: CaptureSubject? {
        CaptureSubject.inferred(for: capture.kind) ?? selectedProfileSubject
    }

    private var diff: CaptureDiff {
        CaptureDiff.compare(capture: capture, history: history)
    }

    private var visibleIdentity: CaptureIdentity {
        CaptureIdentity.make(sourceApp: capture.sourceApp, kind: capture.kind, observations: capture.observations)
    }

    var body: some View {
        GroupBox("Review before saving") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(CapturePresentation.title(for: capture.kind), systemImage: CapturePresentation.icon(for: capture.kind))
                        .font(.headline)
                    Spacer()
                    Text("Review required")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.orange.opacity(0.16), in: Capsule())
                }
                Text("These are literal OCR observations. Machiss will not expand abbreviations or add missing context.")
                    .foregroundStyle(.secondary)
                if capture.kind == .bumbleThread || capture.kind == .hingeThread {
                    GroupBox("Visible identity") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(visibleIdentity.displayName)
                                .font(.title3.weight(.semibold))
                            Text(visibleIdentity.displayName.count <= 2
                                 ? "Only an initial is visible. Confirm the conversation before saving."
                                 : "This is the name or label visible in the captured header; Machiss does not infer anything beyond it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(diff.isFresh ? "New since last approved capture" : "No new visible text detected", systemImage: diff.isFresh ? "sparkles" : "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                        if let previousCaptureAt = diff.previousCaptureAt {
                            Text("Compared with capture \(previousCaptureAt).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("This is the first approved capture in this workspace.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(diff.newVisibleText, id: \.self) { text in
                            Text(text).font(.callout).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if CaptureSubject.inferred(for: capture.kind) == nil, capture.kind != .unrecognized {
                    Picker("This profile belongs to", selection: $selectedProfileSubject) {
                        Text("Choose before saving").tag(CaptureSubject?.none)
                        Text("My profile").tag(CaptureSubject?.some(.ownerProfile))
                        Text("Match profile").tag(CaptureSubject?.some(.matchProfile))
                    }
                    Text("Machiss cannot safely infer whether this visible profile is yours or a match's.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let subject {
                    Text("Capture context: \(subject.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 8) {
                    ForEach(Array(capture.observations.enumerated()), id: \.offset) { _, observation in
                        ObservationRow(observation: observation)
                    }
                }
                Button("Approve & save locally") {
                    guard let subject else { return }
                    onApprove(capture, subject)
                }
                .disabled(capture.kind == .unrecognized || subject == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ObservationRow: View {
    let observation: VisibleObservation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: observation.confidence >= 0.85 ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(observation.confidence >= 0.85 ? .green : .orange)
            Text(observation.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Text("\(Int(observation.confidence * 100))%")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ContextTable: View {
    let section: MatchBoxInboxSection
    let history: MatchImport?

    var body: some View {
        GroupBox(section.title) {
            VStack(alignment: .leading, spacing: 12) {
                if let history {
                    if section == .chats, !history.threads.isEmpty {
                        ForEach(history.threads, id: \.id) { thread in
                            ChatContextRow(
                                thread: thread,
                                profile: history.profiles.first(where: { $0.id == thread.participantID && $0.subject == .matchProfile })
                                    ?? history.profiles.first(where: { $0.id == thread.participantID })
                            )
                        }
                    } else {
                        let profiles = MatchBoxInbox.profiles(in: history, section: section)
                        if !profiles.isEmpty {
                            ForEach(profiles, id: \.id) { profile in
                                ContextRow(profile: profile)
                            }
                        } else {
                            emptyState
                        }
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No \(section.title) yet",
            systemImage: section.symbol,
            description: Text("Capture a Bumble or Hinge screen, review the literal OCR, then save approved context locally.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct ContextRow: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.displayName).font(.headline)
                Spacer()
                Text(profile.subject.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(profile.visibleFacts.prefix(4), id: \.self) { fact in
                Text(CapturePresentation.displayFact(fact)).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ChatContextRow: View {
    let thread: MatchInboxCore.Thread
    let profile: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile?.displayName ?? "Saved conversation")
                    .font(.headline)
                Spacer()
                Text(ThreadClassifier.priority(for: thread).displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ThreadClassifier.priority(for: thread) == .replyNow ? .orange : .secondary)
            }
            if thread.messages.isEmpty {
                Text("No visible message bubbles were saved from this screen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(thread.messages.suffix(3).enumerated()), id: \.offset) { _, message in
                    HStack(alignment: .top, spacing: 8) {
                        Text(message.direction == .incoming ? "THEM" : "YOU")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                }
            }
            Text("Visible local thread • \(thread.messages.count) message\(thread.messages.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension MatchBoxInboxSection {
    var title: String {
        switch self {
        case .chats: "Chats"
        case .likes: "Likes"
        case .profiles: "Profiles"
        case .review: "Needs attention"
        case .suggestions: "Suggestions"
        }
    }

    var symbol: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right.fill"
        case .likes: "heart.fill"
        case .profiles: "person.crop.circle.fill"
        case .review: "brain.head.profile"
        case .suggestions: "sparkles"
        }
    }
}

private extension CaptureSubject {
    var displayName: String {
        switch self {
        case .ownerProfile: "My profile"
        case .matchProfile: "Match profile"
        case .likesContext: "Likes context"
        case .conversationContext: "Conversation context"
        case .legacyUnspecified: "Legacy context"
        }
    }
}

private extension ThreadPriority {
    var displayName: String {
        switch self {
        case .replyNow: "Reply now"
        case .wait: "Wait"
        case .nudgeLater: "Nudge later"
        }
    }
}

private enum CapturePresentation {
    static func title(for kind: ScreenKind) -> String {
        switch kind {
        case .bumbleChats: "Bumble inbox detected"
        case .bumbleLikes: "Bumble likes detected"
        case .bumbleProfile: "Bumble profile detected"
        case .bumbleThread: "Bumble conversation detected"
        case .hingeChats: "Hinge inbox detected"
        case .hingeLikes: "Hinge likes detected"
        case .hingeProfile: "Hinge profile detected"
        case .hingeThread: "Hinge conversation detected"
        case .unrecognized: "Screen needs review"
        }
    }

    static func icon(for kind: ScreenKind) -> String {
        switch kind {
        case .bumbleChats, .bumbleThread, .hingeChats, .hingeThread: "bubble.left.and.bubble.right.fill"
        case .bumbleLikes, .hingeLikes: "heart.fill"
        case .bumbleProfile, .hingeProfile: "person.crop.circle.fill"
        case .unrecognized: "questionmark.app"
        }
    }

    static func displayFact(_ fact: String) -> String {
        fact.replacingOccurrences(of: "visible_text: ", with: "")
    }
}
