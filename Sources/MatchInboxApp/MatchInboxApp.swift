import AppKit
import SwiftUI
import MatchInboxCore
import MatchInboxFoundationModels
import MatchInboxSwiftData
import OSLog

@main
struct MatchInboxApp: App {
    var body: some Scene {
        WindowGroup("Match Box") {
            MatchInboxWorkspace()
        }
        MenuBarExtra(MatchBoxPresentation.menuBarTitle, systemImage: MatchBoxPresentation.menuBarSymbol) {
            Button("Open Match Box") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.title == "Match Box" })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Quit Match Box") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct MatchInboxWorkspace: View {
    @StateObject private var captureService = WindowCaptureService()
    @State private var history: MatchImport?
    @State private var saveError: String?
    @State private var review: String?
    @State private var isReviewing = false
    @State private var saveStatus: String?
    @State private var selection: MatchBoxInboxSection? = .chats
    private let ownerID = "owner"
    private let logger = Logger(subsystem: "com.anupamchugh.matchinbox", category: "history")

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Local inbox") {
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
                Section("Privacy") {
                    Label("On this Mac", systemImage: "lock")
                }
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Match Box").font(.largeTitle.bold())
                            Text("See the signal. Keep the control.")
                                .font(.title3).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("On this Mac", systemImage: "lock.fill")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                    }
                    Text("Match Box never sends, likes, swipes, or matches. It turns the screen you choose into reviewable local context.")
                        .foregroundStyle(.secondary)

                    capturePanel

                    if let capture = captureService.capture {
                        CapturePreview(capture: capture, onApprove: approve)
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

                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text(LocalDraftProvider.availability.description)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .task { loadHistory() }
    }

    private func count(for section: MatchBoxInboxSection) -> Int {
        guard let history else { return 0 }
        switch section {
        case .chats:
            return max(history.threads.count, MatchBoxInbox.profiles(in: history, section: section).count)
        case .likes, .profiles:
            return MatchBoxInbox.profiles(in: history, section: section).count
        case .review:
            return history.profiles.isEmpty ? 0 : 1
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
        GroupBox("Capture") {
            VStack(alignment: .leading, spacing: 10) {
                Text("With iPhone Mirroring open, capture its currently visible window. Text is recognized on this Mac; the screenshot is not retained.")
                Button {
                    Task { await captureService.captureIPhoneMirroring() }
                } label: {
                    Label(captureService.isCapturing ? "Capturing…" : "Capture iPhone Mirroring", systemImage: "viewfinder")
                }
                .disabled(captureService.isCapturing)
                Button {
                    captureService.importMirroirDevelopmentPreview()
                } label: {
                    Label("Import Mirroir test preview", systemImage: "wrench.and.screwdriver")
                }
                .disabled(captureService.isCapturing)
                Text("Development only. It imports a local preview file and still requires review before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
}

private struct CapturePreview: View {
    let capture: ScreenCapture
    let onApprove: (ScreenCapture, CaptureSubject) -> Void
    @State private var selectedProfileSubject: CaptureSubject?

    init(capture: ScreenCapture, onApprove: @escaping (ScreenCapture, CaptureSubject) -> Void) {
        self.capture = capture
        self.onApprove = onApprove
        _selectedProfileSubject = State(initialValue: nil)
    }

    private var subject: CaptureSubject? {
        CaptureSubject.inferred(for: capture.kind) ?? selectedProfileSubject
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
                Text("These are literal OCR observations. Match Box will not expand abbreviations or add missing context.")
                    .foregroundStyle(.secondary)
                if CaptureSubject.inferred(for: capture.kind) == nil, capture.kind != .unrecognized {
                    Picker("This profile belongs to", selection: $selectedProfileSubject) {
                        Text("Choose before saving").tag(CaptureSubject?.none)
                        Text("My profile").tag(CaptureSubject?.some(.ownerProfile))
                        Text("Match profile").tag(CaptureSubject?.some(.matchProfile))
                    }
                    Text("Match Box cannot safely infer whether this visible profile is yours or a match's.")
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
                Button("Save approved context") {
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
        case .review: "Review"
        }
    }

    var symbol: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right.fill"
        case .likes: "heart.fill"
        case .profiles: "person.crop.circle.fill"
        case .review: "brain.head.profile"
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
