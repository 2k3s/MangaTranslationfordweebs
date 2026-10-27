import AppKit
import SwiftUI

struct OverlayTranslationBox: Identifiable {
    let id = UUID()
    // Normalized 0...1 coordinates within the current selection rectangle (top-left origin).
    let normalizedRect: CGRect
    let text: String
}

final class OverlaySelectionStore: ObservableObject {
    static let shared = OverlaySelectionStore()

    private static let rectDefaultsKey = "TransManga.selectionNormalizedRect"
    private static let fontSizeDefaultsKey = "TransManga.overlayFontSize"
    private static let opacityDefaultsKey = "TransManga.cardOpacity"

    // Normalized coordinates: 0...1 across the screen.
    @Published var normalizedRect: CGRect {
        didSet {
            let values = [
                Double(normalizedRect.origin.x),
                Double(normalizedRect.origin.y),
                Double(normalizedRect.size.width),
                Double(normalizedRect.size.height)
            ]
            UserDefaults.standard.set(values, forKey: Self.rectDefaultsKey)
        }
    }

    @Published var overlayFontSize: Double {
        didSet {
            UserDefaults.standard.set(overlayFontSize, forKey: Self.fontSizeDefaultsKey)
        }
    }

    @Published var cardOpacity: Double {
        didSet {
            UserDefaults.standard.set(cardOpacity, forKey: Self.opacityDefaultsKey)
        }
    }

    @Published var translationBoxes: [OverlayTranslationBox] = []
    @Published var areCardsHidden = false
    @Published var isWorking = false
    @Published var isAutoWatching = true
    @Published var isClickThrough = false
    @Published var statusError: String?

    var overlayWindowID: CGWindowID?

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.rectDefaultsKey) as? [Double],
           saved.count == 4 {
            let width = min(max(0.15, saved[2]), 1.0)
            let height = min(max(0.15, saved[3]), 1.0)
            let x = min(max(0.0, saved[0]), 1.0 - width)
            let y = min(max(0.0, saved[1]), 1.0 - height)
            self.normalizedRect = CGRect(x: x, y: y, width: width, height: height)
        } else {
            self.normalizedRect = CGRect(
                x: 0.15, y: 0.12, width: 0.70, height: 0.72
            )
        }

        let savedFontSize = UserDefaults.standard.double(forKey: Self.fontSizeDefaultsKey)
        self.overlayFontSize = (10.0...22.0).contains(savedFontSize) ? savedFontSize : 13.0

        let savedOpacity = UserDefaults.standard.double(forKey: Self.opacityDefaultsKey)
        self.cardOpacity = (0.70...1.0).contains(savedOpacity) ? savedOpacity : 0.96
    }
}

final class OverlayWindowController {
    private var window: NSWindow?
    private var isClickThrough = false

    func show() {
        guard window == nil, let screen = NSScreen.main else { return }

        let overlay = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        overlay.isReleasedWhenClosed = false
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.ignoresMouseEvents = false
        overlay.contentView = NSHostingView(
            rootView: SelectionOverlayView()
        )

        window = overlay
        overlay.orderFrontRegardless()

        OverlaySelectionStore.shared.overlayWindowID =
            CGWindowID(overlay.windowNumber)
    }

    func toggleClickThrough() {
        guard let window else { return }

        isClickThrough.toggle()
        window.ignoresMouseEvents = isClickThrough
        OverlaySelectionStore.shared.isClickThrough = isClickThrough

        if !isClickThrough {
            window.orderFrontRegardless()
        }

        print(isClickThrough
            ? "Overlay: click-through enabled"
            : "Overlay: selection editing enabled")
    }
}

private struct OverlayLiquidGlassCapsule: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct SelectionOverlayView: View {
    @ObservedObject private var store = OverlaySelectionStore.shared
    @State private var dragStart: CGRect?

    private let handleSize: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geometry in
                let size = geometry.size
                let selection = store.normalizedRect
                let rect = CGRect(
                    x: selection.minX * size.width,
                    y: selection.minY * size.height,
                    width: selection.width * size.width,
                    height: selection.height * size.height
                )

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())

                    // Selection frame with subtle animated glass rim in Edit mode
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(store.isClickThrough ? Color.clear : Color.cyan.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(store.isClickThrough ? 0.25 : 0.85),
                                            Color.cyan.opacity(store.isClickThrough ? 0.22 : 0.90),
                                            Color.blue.opacity(store.isClickThrough ? 0.15 : 0.65),
                                            Color.cyan.opacity(store.isClickThrough ? 0.22 : 0.90),
                                            Color.white.opacity(store.isClickThrough ? 0.25 : 0.85)
                                        ]),
                                        center: .center,
                                        angle: .radians(phase * 0.5)
                                    ),
                                    lineWidth: store.isClickThrough ? 1 : 2
                                )
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStart == nil {
                                        dragStart = store.normalizedRect
                                        if !store.translationBoxes.isEmpty {
                                            store.translationBoxes = []
                                        }
                                    }
                                    guard let start = dragStart else { return }

                                    store.normalizedRect.origin.x = min(
                                        max(0, start.minX + value.translation.width / size.width),
                                        1 - start.width
                                    )
                                    store.normalizedRect.origin.y = min(
                                        max(0, start.minY + value.translation.height / size.height),
                                        1 - start.height
                                    )
                                }
                                .onEnded { _ in dragStart = nil }
                        )

                    if !store.areCardsHidden {
                        ForEach(store.translationBoxes) { box in
                            let bubbleRect = CGRect(
                                x: rect.minX + box.normalizedRect.minX * rect.width,
                                y: rect.minY + box.normalizedRect.minY * rect.height,
                                width: box.normalizedRect.width * rect.width,
                                height: box.normalizedRect.height * rect.height
                            )

                            Text(box.text.uppercased())
                                .font(mangaOverlayFont(size: CGFloat(store.overlayFontSize)))
                                .tracking(0.3)
                                .lineSpacing(1)
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.45)
                                .padding(6)
                                .frame(
                                    width: max(84, bubbleRect.width),
                                    height: max(48, bubbleRect.height)
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(store.cardOpacity))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.18), lineWidth: 1)
                                }
                                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                                .position(x: bubbleRect.midX, y: bubbleRect.midY)
                                .allowsHitTesting(false)
                        }
                    }

                    if !store.isClickThrough {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(.white)
                                .overlay {
                                    Circle()
                                        .stroke(Color.cyan, lineWidth: 2)
                                }
                                .shadow(color: Color.black.opacity(0.25), radius: 3)
                                .frame(width: handleSize, height: handleSize)
                                .position(handlePoint(index, rect: rect))
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if dragStart == nil {
                                                dragStart = store.normalizedRect
                                                if !store.translationBoxes.isEmpty {
                                                    store.translationBoxes = []
                                                }
                                            }
                                            guard let start = dragStart else { return }

                                            let dx = value.translation.width / size.width
                                            let dy = value.translation.height / size.height
                                            var r = start

                                            switch index {
                                            case 0: // Top-left
                                                r.origin.x = min(start.maxX - 0.15, max(0, start.minX + dx))
                                                r.origin.y = min(start.maxY - 0.15, max(0, start.minY + dy))
                                                r.size.width = start.maxX - r.minX
                                                r.size.height = start.maxY - r.minY
                                            case 1: // Top-right
                                                r.size.width = max(0.15, min(1 - start.minX, start.width + dx))
                                                r.origin.y = min(start.maxY - 0.15, max(0, start.minY + dy))
                                                r.size.height = start.maxY - r.minY
                                            case 2: // Bottom-left
                                                r.origin.x = min(start.maxX - 0.15, max(0, start.minX + dx))
                                                r.size.width = start.maxX - r.minX
                                                r.size.height = max(0.15, min(1 - start.minY, start.height + dy))
                                            default: // Bottom-right
                                                r.size.width = max(0.15, min(1 - start.minX, start.width + dx))
                                                r.size.height = max(0.15, min(1 - start.minY, start.height + dy))
                                            }

                                            store.normalizedRect = r
                                        }
                                        .onEnded { _ in dragStart = nil }
                                )
                        }
                    }

                    // Live behind-window Liquid Glass HUD pill
                    HStack(spacing: 7) {
                        if store.isWorking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Translating…")
                        } else if let statusError = store.statusError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(statusError)
                                .lineLimit(1)
                        } else {
                            Circle()
                                .fill(store.isAutoWatching ? Color.green : Color.secondary)
                                .frame(width: 7, height: 7)
                                .shadow(color: store.isAutoWatching ? Color.green.opacity(0.8) : .clear, radius: 4)
                            Text(
                                "Watch \(store.isAutoWatching ? "ON" : "OFF") (⌃⌥W) • \(store.isClickThrough ? "Reading" : "Edit") (⌃⌥O) • \(store.areCardsHidden ? "Hidden" : "Peek") (⌃⌥H)"
                            )
                        }
                    }
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        ZStack {
                            OverlayLiquidGlassCapsule()
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.cyan.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .clipShape(Capsule())
                    }
                    .overlay {
                        Capsule()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.65),
                                        Color.cyan.opacity(0.35),
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.65)
                                    ]),
                                    center: .center,
                                    angle: .radians(phase * 0.6)
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
                    .position(
                        x: min(max(rect.midX, 240), size.width - 240),
                        y: max(20, rect.minY - 20)
                    )
                    .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func mangaOverlayFont(size: CGFloat) -> Font {
        let preferredMangaFonts = [
            "CCWildWords-Roman",
            "WildWords-Roman",
            "AnimeAce2.0BB",
            "AnimeAce",
            "KomikaAxis",
            "ChalkboardSE-Bold",
            "ComicSansMS-Bold"
        ]

        for fontName in preferredMangaFonts where NSFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size)
        }

        return .system(size: size, weight: .bold, design: .rounded)
    }

    private func handlePoint(_ index: Int, rect: CGRect) -> CGPoint {
        switch index {
        case 0: CGPoint(x: rect.minX, y: rect.minY)
        case 1: CGPoint(x: rect.maxX, y: rect.minY)
        case 2: CGPoint(x: rect.minX, y: rect.maxY)
        default: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
