import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = TransMangaModel()
    @ObservedObject private var store = OverlaySelectionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TransManga").font(.largeTitle.bold())
                    Text("Offline Japanese → English screen translator")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Label("Shortcuts", systemImage: "keyboard")
                Spacer()
                Text("⌃⌥M Capture • ⌃⌥W Watch • ⌃⌥O Click-Through • ⌃⌥H Peek")
                    .font(.system(.callout, design: .monospaced).bold())
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.captureAndRecognize() }
                } label: {
                    Label("Capture & Translate", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.toggleAutoWatch()
                } label: {
                    Label(
                        model.isAutoWatching ? "Auto-Watch: On" : "Auto-Watch: Off",
                        systemImage: model.isAutoWatching ? "eye.fill" : "eye"
                    )
                }
                .buttonStyle(.bordered)
                .tint(model.isAutoWatching ? .green : nil)

                Button {
                    store.areCardsHidden.toggle()
                } label: {
                    Label(
                        store.areCardsHidden ? "Show Cards" : "Peek Original",
                        systemImage: store.areCardsHidden ? "rectangle.stack.fill" : "rectangle.stack"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(store.translationBoxes.isEmpty)

                Button("Clear") { model.reset() }
                    .buttonStyle(.bordered)

                Button("Clear Cache") { model.clearTranslationCache() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 20) {
                HStack(spacing: 8) {
                    Text("Font Size: \(Int(store.overlayFontSize)) pt")
                        .font(.caption)
                        .frame(width: 95, alignment: .leading)
                    Slider(value: $store.overlayFontSize, in: 10...20, step: 1)
                }

                HStack(spacing: 8) {
                    Text("Bubble Opacity: \(Int(store.cardOpacity * 100))%")
                        .font(.caption)
                        .frame(width: 125, alignment: .leading)
                    Slider(value: $store.cardOpacity, in: 0.75...1.0, step: 0.05)
                }
            }

            if model.isWorking {
                ProgressView("Reading & translating screen…")
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            GroupBox("Detected Japanese text") {
                ScrollView {
                    Text(model.recognizedText.isEmpty
                         ? "No text detected yet. Position the selection box over a manga page, then press ⌃⌥O to read."
                         : model.recognizedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(minHeight: 120)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        model.recognizedText,
                        forType: .string
                    )
                } label: {
                    Label("Copy Japanese text", systemImage: "doc.on.doc")
                }
                .disabled(model.recognizedText.isEmpty)
            }

            GroupBox("English translation") {
                ScrollView {
                    Text(model.translatedText.isEmpty
                         ? (model.isWorking && !model.recognizedText.isEmpty
                            ? "Translating with local model…"
                            : "English translation will appear here after capture.")
                         : model.translatedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(minHeight: 120)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        model.translatedText,
                        forType: .string
                    )
                } label: {
                    Label("Copy English translation", systemImage: "doc.on.doc")
                }
                .disabled(model.translatedText.isEmpty)
            }

            Spacer(minLength: 0)

            Text("Privacy: screenshots and translations run 100% locally on your Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .onReceive(NotificationCenter.default.publisher(for: .transMangaTranslate)) { _ in
               Task { await model.captureAndRecognize() }
           }
           .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleAutoWatch)) { _ in
               model.toggleAutoWatch()
           }
           .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleCards)) { _ in
               store.areCardsHidden.toggle()
           }
    }
}
