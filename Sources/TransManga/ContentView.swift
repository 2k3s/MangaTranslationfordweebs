import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = TransMangaModel()
    @ObservedObject private var store = OverlaySelectionStore.shared
    @State private var hoverPoint: CGPoint = CGPoint(x: 320, y: 240)
    @State private var isHoveringWindow = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                // Live behind-window Liquid Glass backdrop that refracts desktop & browser motion.
                LiquidGlassWindowBackdrop(material: .hudWindow)
                    .ignoresSafeArea()

                // Subtle moving refractive caustic glow that reacts to pointer + time.
                GeometryReader { proxy in
                    let size = proxy.size
                    let normX = size.width > 0 ? hoverPoint.x / size.width : 0.5
                    let normY = size.height > 0 ? hoverPoint.y / size.height : 0.5
                    let driftX = cos(phase * 0.7) * 0.08
                    let driftY = sin(phase * 0.5) * 0.08

                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(model.isWorking ? 0.22 : 0.12),
                            Color.blue.opacity(0.06),
                            Color.clear
                        ],
                        center: UnitPoint(
                            x: min(max(0.1, (isHoveringWindow ? normX : 0.5) + driftX), 0.9),
                            y: min(max(0.1, (isHoveringWindow ? normY : 0.35) + driftY), 0.9)
                        ),
                        startRadius: 10,
                        endRadius: 360
                    )
                    .blendMode(.plusLighter)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 14) {
                    // Header bar
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.cyan.opacity(0.35),
                                            Color.blue.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.65), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                }

                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("TransManga")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                StatusPill(
                                    isWorking: model.isWorking,
                                    isWatching: model.isAutoWatching
                                )
                            }
                            Text("Local VisionKit OCR • Ollama qwen2.5:7b")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Compact hotkey pills
                        HStack(spacing: 6) {
                            ShortcutBadge(keys: "⌃⌥M", label: "Capture")
                            ShortcutBadge(keys: "⌃⌥W", label: "Watch")
                            ShortcutBadge(keys: "⌃⌥O", label: "Read")
                            ShortcutBadge(keys: "⌃⌥H", label: "Peek")
                        }
                    }

                    // Action toolbar + sliders inside a single sleek glass strip
                    LiquidGlassCard(phase: phase, cornerRadius: 16, padding: 12) {
                        VStack(spacing: 10) {
                            HStack(spacing: 8) {
                                GlassPillButton(
                                    title: "Translate Now",
                                    icon: "sparkles",
                                    isProminent: true
                                ) {
                                    Task { await model.captureAndRecognize() }
                                }

                                GlassPillButton(
                                    title: model.isAutoWatching ? "Watch: On" : "Watch: Off",
                                    icon: model.isAutoWatching ? "eye.fill" : "eye.slash",
                                    isActive: model.isAutoWatching
                                ) {
                                    model.toggleAutoWatch()
                                }

                                GlassPillButton(
                                    title: store.areCardsHidden ? "Show Cards" : "Peek Raw",
                                    icon: store.areCardsHidden ? "rectangle.stack.fill" : "rectangle.stack",
                                    isActive: store.areCardsHidden
                                ) {
                                    store.areCardsHidden.toggle()
                                }
                                .disabled(store.translationBoxes.isEmpty)

                                Spacer()

                                GlassPillButton(title: "Clear", icon: "xmark.circle") {
                                    model.reset()
                                }

                                GlassPillButton(title: "Purge Cache", icon: "arrow.triangle.2.circlepath") {
                                    model.clearTranslationCache()
                                }
                            }

                            Divider()
                                .overlay(Color.white.opacity(0.12))

                            HStack(spacing: 20) {
                                HStack(spacing: 8) {
                                    Image(systemName: "textformat.size")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(store.overlayFontSize)) pt")
                                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                        .frame(width: 38, alignment: .leading)
                                    Slider(value: $store.overlayFontSize, in: 10...20, step: 1)
                                        .tint(.cyan)
                                }

                                HStack(spacing: 8) {
                                    Image(systemName: "circle.lefthalf.filled")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(store.cardOpacity * 100))%")
                                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                        .frame(width: 38, alignment: .leading)
                                    Slider(value: $store.cardOpacity, in: 0.75...1.0, step: 0.05)
                                        .tint(.cyan)
                                }
                            }
                        }
                    }

                    if let error = model.error {
                        LiquidGlassCard(phase: phase, cornerRadius: 12, padding: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                    }

                    // Side-by-side sleek Liquid Glass panels for Japanese & English
                    HStack(spacing: 12) {
                        LiquidGlassTextPanel(
                            title: "JAPANESE OCR",
                            subtitle: "VisionKit Live Text",
                            text: model.recognizedText,
                            placeholder: "Position the selection frame over a manga page and press ⌃⌥O to read hands-free.",
                            phase: phase
                        )

                        LiquidGlassTextPanel(
                            title: "ENGLISH TRANSLATION",
                            subtitle: "qwen2.5:7b Local",
                            text: model.translatedText,
                            placeholder: model.isWorking && !model.recognizedText.isEmpty
                                ? "Refracting & translating speech bubbles…"
                                : "Translated dialogue appears here and in-place over each speech bubble.",
                            phase: phase + 1.4
                        )
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
        .onContinuousHover { hoverPhase in
            switch hoverPhase {
            case .active(let location):
                hoverPoint = location
                isHoveringWindow = true
            case .ended:
                isHoveringWindow = false
            }
        }
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

// MARK: - Live Behind-Window Liquid Glass AppKit Bridge

struct LiquidGlassWindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true

        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

// MARK: - Reusable Liquid Glass Components

private struct LiquidGlassCard<Content: View>: View {
    let phase: Double
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        let angle = Angle.radians(phase * 0.45)

        content
            .padding(padding)
            .background {
                ZStack {
                    LiquidGlassWindowBackdrop(material: .popover)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.03),
                            Color.cyan.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                // Dynamic refractive rim highlight that shifts with motion phase
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.55),
                                Color.cyan.opacity(0.28),
                                Color.white.opacity(0.08),
                                Color.blue.opacity(0.22),
                                Color.white.opacity(0.55)
                            ]),
                            center: .center,
                            angle: angle
                        ),
                        lineWidth: 1.1
                    )
            }
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

private struct LiquidGlassTextPanel: View {
    let title: String
    let subtitle: String
    let text: String
    let placeholder: String
    let phase: Double

    @State private var copied = false

    var body: some View {
        LiquidGlassCard(phase: phase, cornerRadius: 16, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(subtitle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }

                Divider()
                    .overlay(Color.white.opacity(0.1))

                ScrollView {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 13, weight: text.isEmpty ? .regular : .medium))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct GlassPillButton: View {
    let title: String
    let icon: String
    var isProminent: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(
                        isProminent
                            ? LinearGradient(
                                colors: [
                                    Color.cyan.opacity(isHovering ? 0.55 : 0.42),
                                    Color.blue.opacity(isHovering ? 0.45 : 0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    isActive
                                        ? Color.green.opacity(isHovering ? 0.35 : 0.25)
                                        : Color.white.opacity(isHovering ? 0.18 : 0.10),
                                    Color.white.opacity(isHovering ? 0.08 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
            }
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovering ? 0.65 : 0.35),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ShortcutBadge: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        }
    }
}

private struct StatusPill: View {
    let isWorking: Bool
    let isWatching: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isWorking {
                ProgressView()
                    .controlSize(.mini)
                Text("Translating")
            } else {
                Circle()
                    .fill(isWatching ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                    .shadow(color: isWatching ? Color.green.opacity(0.8) : .clear, radius: 4)
                Text(isWatching ? "Live Watch" : "Manual")
            }
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        }
    }
}
