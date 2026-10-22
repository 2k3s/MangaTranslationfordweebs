import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = MangaLensModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MangaLens").font(.largeTitle.bold())
                    Text("Offline Japanese → English screen translator")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Label("Shortcut", systemImage: "keyboard")
                Spacer()
                Text("⌃ ⌥ M").font(.system(.body, design: .monospaced).bold())
            }

            Text("Press the shortcut to capture the screen and detect Japanese text. This prototype currently implements screen capture and OCR; local translation and text replacement are the next integration steps.")
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Task { await model.captureAndRecognize() }
                } label: {
                    Label("Capture & detect text", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)

                Button("Clear results") { model.reset() }
                    .buttonStyle(.bordered)
            }

            if model.isWorking {
                ProgressView("Reading screen…")
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            GroupBox("Detected Japanese text") {
                ScrollView {
                    Text(model.recognizedText.isEmpty
                         ? "No text detected yet. Open a manga page, grant Screen Recording permission when prompted, then capture."
                         : model.recognizedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(minHeight: 160)
            }

            Spacer(minLength: 0)

            Text("Privacy: screenshots are processed locally and are not uploaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .onReceive(NotificationCenter.default.publisher(for: .mangaLensTranslate)) { _ in
            Task { await model.captureAndRecognize() }
        }
    }
}
