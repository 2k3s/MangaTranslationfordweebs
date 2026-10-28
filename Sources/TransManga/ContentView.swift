import SwiftUI
import AppKit

struct LiquidGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = TransMangaModel()
    @ObservedObject private var store = OverlaySelectionStore.shared
    @State private var hoverPoint: CGPoint = CGPoint(x: 320, y: 240)
    @State private var isHoveringWindow = false
    @State private var showGlossary = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            // Interactive cursor-reactive refraction highlight
            RadialGradient(
                colors: [
                    Color.cyan.opacity(isHoveringWindow ? 0.22 : 0.08),
                    Color.purple.opacity(isHoveringWindow ? 0.12 : 0.04),
                    Color.clear
                ],
                center: UnitPoint(
                    x: min(max(hoverPoint.x / 720, 0), 1),
                    y: min(max(hoverPoint.y / 540, 0), 1)
                ),
                startRadius: 12,
                endRadius: 340
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                // Header bar
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TransManga")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(model.statusMessage)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showGlossary.toggle()
                        }
                    } label: {
                        Label("Glossary (\(model.glossary.count))", systemImage: "character.book.closed")
                    }
                    .buttonStyle(.bordered)
                }

                // Quick action pills
                HStack(spacing: 10) {
                    Button {
                        model.captureAndTranslate()
                    } label: {
                        Label("Translate Now (⌃⌥M)", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(model.isBusy)

                    Button {
                        model.toggleClickThrough()
                    } label: {
                        Label(
                            store.isClickThrough ? "Unlock Box (⌃⌥O)" : "Lock Reading Mode (⌃⌥O)",
                            systemImage: store.isClickThrough ? "lock.fill" : "lock.open"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.toggleAutoWatch()
                    } label: {
                        Label(
                            store.isAutoWatching ? "Auto-Watch: ON (⌃⌥W)" : "Auto-Watch: OFF (⌃⌥W)",
                            systemImage: "eye"
                        )
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.toggleOverlayCards()
                    } label: {
                        Label(
                            store.showTranslationCards ? "Peek Original (⌃⌥H)" : "Show Cards (⌃⌥H)",
                            systemImage: store.showTranslationCards ? "eye.slash" : "text.bubble"
                        )
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                // Collapsible Series Glossary Drawer
                if showGlossary {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Series Glossary (keeps character names & terms consistent)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("+ Add Term") {
                                model.addGlossaryEntry()
                            }
                            .controlSize(.small)
                        }

                        if model.glossary.isEmpty {
                            Text("No glossary terms yet. Click '+ Add Term' to lock character names (e.g. 星架 → Seika).")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach($model.glossary) { $entry in
                                        HStack(spacing: 8) {
                                            TextField("Japanese (e.g. 星架)", text: $entry.japanese)
                                                .textFieldStyle(.roundedBorder)
                                            Text("→")
                                                .foregroundColor(.secondary)
                                            TextField("English (e.g. Seika)", text: $entry.english)
                                                .textFieldStyle(.roundedBorder)
                                            Button {
                                                model.removeGlossaryEntry(id: entry.id)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 110)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
                }

                // Detected bubbles list
                ScrollView {
                    if model.blocks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No bubbles captured yet")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text("Drag the cyan overlay box over a manga page and press ⌃⌥M.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.blocks) { block in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("#\(block.index)")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.cyan)
                                        .frame(width: 28, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(block.japaneseText)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .textSelection(.enabled)
                                        Text(block.englishText)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .textSelection(.enabled)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 680, minHeight: 460)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
                isHoveringWindow = true
            case .ended:
                isHoveringWindow = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaTranslate)) { _ in
            model.captureAndTranslate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleClickThrough)) { _ in
            model.toggleClickThrough()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleAutoWatch)) { _ in
            model.toggleAutoWatch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleCards)) { _ in
            model.toggleOverlayCards()
        }
    }
}
