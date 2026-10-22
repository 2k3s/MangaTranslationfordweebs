import AppKit
import Vision
import ImageIO

@MainActor
final class MangaLensModel: ObservableObject {
    @Published var recognizedText = ""
    @Published var error: String?
    @Published var isWorking = false

    func reset() {
        recognizedText = ""
        error = nil
    }

    func captureAndRecognize() async {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let image = try ScreenCapture.captureMainDisplay()
            recognizedText = try await JapaneseOCR.recognize(in: image)
            if recognizedText.isEmpty {
                recognizedText = "No Japanese text was detected. Try zooming in or capturing a page with larger text."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum ScreenCaptureError: LocalizedError {
    case noDisplayImage

    var errorDescription: String? {
        switch self {
        case .noDisplayImage:
            return "Couldn't capture the display. Check System Settings → Privacy & Security → Screen Recording, then quit and reopen MangaLens."
        }
    }
}

enum ScreenCapture {
    static func captureMainDisplay() throws -> CGImage {
        // CGWindowListCreateImage is deprecated in newer macOS SDKs but remains
        // a simple prototype path. A production build should migrate to ScreenCaptureKit.
        guard let image = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .ignoreFraming]
        ) else {
            throw ScreenCaptureError.noDisplayImage
        }
        return image
    }
}

enum JapaneseOCR {
    static func recognize(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> (CGFloat, String)? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return (observation.boundingBox.midY, candidate.string)
                }
                // Screen coordinates are normalized from the bottom-left; read top-to-bottom.
                let text = lines.sorted { $0.0 > $1.0 }.map(\.1).joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ja-JP"]
            request.minimumTextHeight = 0.008

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
