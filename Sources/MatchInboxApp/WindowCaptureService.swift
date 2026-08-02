import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision
import OSLog
import MatchInboxCore

enum WindowCaptureError: LocalizedError {
    case iPhoneMirroringWindowNotFound
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .iPhoneMirroringWindowNotFound:
            "Open iPhone Mirroring, then try Capture again."
        case .noRecognizedText:
            "No readable text was found in the selected iPhone Mirroring window."
        }
    }
}

@MainActor
final class WindowCaptureService: ObservableObject {
    private let logger = Logger(subsystem: "com.anupamchugh.matchinbox", category: "capture")
    @Published private(set) var capture: ScreenCapture?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCapturing = false

    func captureIPhoneMirroring() async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.title?.localizedCaseInsensitiveContains("iPhone Mirroring") == true }) else {
                throw WindowCaptureError.iPhoneMirroringWindowNotFound
            }
            let image = try await screenshot(of: window)
            let observations = try recognize(image)
            let kind = ScreenClassifier.classify(visibleText: observations.map { $0.text })
            capture = ScreenCapture(
                sourceApp: kind.sourceApp,
                kind: kind,
                observations: ProfileObservationAdapter.label(observations, for: kind),
                capturedAt: ISO8601DateFormatter().string(from: Date())
            )
            logger.notice("Captured screen kind=\(kind.rawValue, privacy: .public) observations=\(observations.count, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func importMirroirDevelopmentPreview() {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }
        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let url = MirroirBridge.previewURL(applicationSupport: applicationSupport)
            capture = try JSONDecoder().decode(ScreenCapture.self, from: Data(contentsOf: url))
            logger.notice("Imported development bridge preview kind=\(self.capture?.kind.rawValue ?? "unknown", privacy: .public)")
        } catch {
            errorMessage = "No local Mirroir development preview was found. Export one with the Match Box CLI first."
            logger.error("Development bridge import failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func screenshot(of window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * 2))
        configuration.height = max(1, Int(window.frame.height * 2))
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func recognize(_ image: CGImage) throws -> [VisibleObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        let observations = (request.results ?? []).compactMap { result -> VisibleObservation? in
            guard let candidate = result.topCandidates(1).first, !candidate.string.isEmpty else { return nil }
            return VisibleObservation(
                field: "visible_text",
                text: candidate.string,
                confidence: Double(candidate.confidence),
                positionX: Double(result.boundingBox.midX)
            )
        }
        guard !observations.isEmpty else { throw WindowCaptureError.noRecognizedText }
        return observations
    }
}
