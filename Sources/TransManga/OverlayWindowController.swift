import SwiftUI
import AppKit
import Combine

struct OrientedLineMask: Identifiable {
    let id = UUID()
    /// Normalized 0...1 center and oriented size relative to the captured region
    let centerX: CGFloat
    let centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotationRadians: Double
    /// Axis-aligned box in normalized 0...1 coordinates for local background color sampling
    let sampleBox: CGRect
    /// Sampled local background color right behind this specific line
    var backgroundColor: Color = .white
}

struct OverlayTranslationBox: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
    /// Axis-aligned normalized bounding box (0...1, top-left origin)
    let boundingBox: CGRect
    /// Oriented center & size in normalized 0...1 coordinates
    let centerX: CGFloat
    let centerY: CGFloat
    let orientedWidth: CGFloat
    let orientedHeight: CGFloat
    let rotationRadians: Double
    /// Tight per-line masks (including furigana) so all original ink is covered
    let lineMasks: [OrientedLineMask]
    /// Sampled background color of the manga bubble
    let backgroundColor: Color
    /// Contrasting text color (dark ink on light/grey bubbles, light ink on dark bubbles)
    let textColor: Color
}

final class OverlaySelectionStore: ObservableObject {
    static let shared = OverlaySelectionStore()

    @Published var normalizedSelection = CGRect(x: 0.15, y: 0.15, width: 0.55, height: 0.65)
    @Published var isClickThrough = false
    @Published var showTranslationCards = true
    @Published var isVisible = true
    @Published var isAutoWatching = false
    @Published var overlayBoxes: [OverlayTranslationBox] = []

    var onTranslateRequested: (() -> Void)?
    var onToggleAutoWatch: (() -> Void)?
    var onToggleClickThrough: (() -> Void)?

    private init() {}
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindowController: NSObject {
    private var panel: OverlayPanel?
    private var cancellables = Set<AnyCancellable>()
    let store = OverlaySelectionStore.shared

    override init() {
        super.init()
        store.$isClickThrough
            .receive(on: RunLoop.main)
            .sink { [weak self] clickThrough in
                self?.panel?.ignoresMouseEvents = clickThrough
            }
            .store(in: &cancellables)
    }

    func showOverlay() {
        if panel == nil {
            createPanel()
        }
        guard let panel = panel else { return }
        if let screen = NSScreen.main {
            panel.setFrame(screen.frame, display: true)
        }
        panel.orderFrontRegardless()
        store.isVisible = true
    }

    func hideOverlay() {
        panel?.orderOut(nil)
        store.isVisible = false
    }

    func toggleOverlay() {
        if panel == nil {
            createPanel()
        }
        guard let panel = panel else { return }

        if panel.isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    func setClickThrough(_ enabled: Bool) {
        store.isClickThrough = enabled
        panel?.ignoresMouseEvents = enabled
    }

    func currentScreenSelectionRect() -> CGRect? {
        guard let screen = panel?.screen ?? NSScreen.main else { return nil }
        let screenFrame = screen.frame
        let sel = store.normalizedSelection

        let x = screenFrame.minX + sel.minX * screenFrame.width
        let width = sel.width * screenFrame.width
        let height = sel.height * screenFrame.height

        let screenTopY = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let topDownScreenMinY = screenTopY - screenFrame.maxY
        let y = topDownScreenMinY + sel.minY * screenFrame.height

        return CGRect(x: x, y: y, width: width, height: height)
    }

    func setPanelVisibility(_ visible: Bool) {
        if panel == nil {
            createPanel()
        }
        guard let panel = panel else { return }
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func createPanel() {
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = OverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = store.isClickThrough
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = SelectionOverlayView(store: store)
        panel.contentView = NSHostingView(rootView: rootView)
        self.panel = panel
    }
}

struct SelectionOverlayView: View {
    @ObservedObject var store: OverlaySelectionStore
    @State private var dragStartRect: CGRect? = nil
    @State private var resizeStartRect: CGRect? = nil

    var body: some View {
        GeometryReader { geo in
            let rect = store.normalizedSelection
            let boxX = rect.minX * geo.size.width
            let boxY = rect.minY * geo.size.height
            let boxWidth = max(120, rect.width * geo.size.width)
            let boxHeight = max(120, rect.height * geo.size.height)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            store.isClickThrough
                                ? Color.green.opacity(0.45)
                                : Color.cyan.opacity(0.95),
                            style: StrokeStyle(
                                lineWidth: store.isClickThrough ? 1.5 : 2.5,
                                dash: store.isClickThrough ? [8, 6] : []
                            )
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(store.isClickThrough ? 0.0 : 0.015))
                        )

                    if store.showTranslationCards {
                        ForEach(store.overlayBoxes) { box in
                            let cx = box.centerX * boxWidth
                            let cy = box.centerY * boxHeight
                            let rawW = max(28, box.orientedWidth * boxWidth)
                            let rawH = max(20, box.orientedHeight * boxHeight)

                            let isVerticalColumn = rawH > rawW * 1.15 && abs(box.rotationRadians) < 0.05
                            let textFrameW = isVerticalColumn
                                ? min(max(rawW * 1.35, 74), rawW + 34)
                                : max(rawW + 8, 44)
                            let textFrameH = max(rawH + 8, 22)

                            let layout = layoutMangaText(
                                box.text.uppercased(),
                                width: textFrameW,
                                height: textFrameH
                            )

                            ZStack {
                                // 1. Per-line masks (including furigana) using each line's exact local background color
                                ForEach(box.lineMasks) { mask in
                                    let mW = max(14, mask.width * boxWidth + 10)
                                    let mH = max(14, mask.height * boxHeight + 10)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(mask.backgroundColor)
                                        .frame(width: mW, height: mH)
                                        .rotationEffect(.radians(mask.rotationRadians))
                                        .position(
                                            x: mask.centerX * boxWidth,
                                            y: mask.centerY * boxHeight
                                        )
                                }

                                // 2. Word-locked lines: every line has `.lineLimit(1)` so a word can NEVER split mid-word
                                VStack(spacing: 1) {
                                    ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(
                                                size: layout.fontSize,
                                                weight: .bold,
                                                design: .rounded
                                            ))
                                            .foregroundColor(box.textColor)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.35)
                                            .allowsTightening(true)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(box.backgroundColor)
                                )
                                .frame(width: textFrameW, height: textFrameH, alignment: .center)
                                .rotationEffect(.radians(box.rotationRadians))
                                .position(x: cx, y: cy)
                            }
                        }
                    }
                }
                .frame(width: boxWidth, height: boxHeight)
                .position(x: boxX + boxWidth / 2, y: boxY + boxHeight / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !store.isClickThrough else { return }
                            if dragStartRect == nil {
                                dragStartRect = store.normalizedSelection
                            }
                            guard let start = dragStartRect else { return }
                            let dx = value.translation.width / geo.size.width
                            let dy = value.translation.height / geo.size.height

                            var newX = min(max(0.0, start.minX + dx), 1.0 - start.width)
                            var newY = min(max(0.0, start.minY + dy), 1.0 - start.height)
                            newX = max(0.0, newX)
                            newY = max(0.0, newY)

                            store.normalizedSelection = CGRect(
                                x: newX,
                                y: newY,
                                width: start.width,
                                height: start.height
                            )
                        }
                        .onEnded { _ in
                            dragStartRect = nil
                        }
                )

                // Top floating toolbar
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.isClickThrough ? Color.green : Color.cyan)
                            .frame(width: 8, height: 8)
                        Text(store.isClickThrough ? "Reading (⌃⌥O)" : "Region Edit")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }

                    if !store.isClickThrough {
                        Button("Translate (⌃⌥M)") {
                            store.onTranslateRequested?()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .controlSize(.small)

                        Button(store.isAutoWatching ? "Auto: ON (⌃⌥W)" : "Auto: OFF (⌃⌥W)") {
                            store.onToggleAutoWatch?()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(store.isAutoWatching ? .green : .gray)
                        .controlSize(.small)

                        if !store.overlayBoxes.isEmpty {
                            Button(store.showTranslationCards ? "Peek Raw (⌃⌥H)" : "Show EN (⌃⌥H)") {
                                store.showTranslationCards.toggle()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button("Lock (⌃⌥O)") {
                            store.onToggleClickThrough?()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .position(x: boxX + boxWidth / 2, y: max(24, boxY - 22))

                // Bottom-right resize handle
                if !store.isClickThrough {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: boxX + boxWidth, y: boxY + boxHeight)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if resizeStartRect == nil {
                                        resizeStartRect = store.normalizedSelection
                                    }
                                    guard let start = resizeStartRect else { return }
                                    let dw = value.translation.width / geo.size.width
                                    let dh = value.translation.height / geo.size.height

                                    let newW = min(max(0.10, start.width + dw), 1.0 - start.minX)
                                    let newH = min(max(0.10, start.height + dh), 1.0 - start.minY)

                                    store.normalizedSelection = CGRect(
                                        x: start.minX,
                                        y: start.minY,
                                        width: newW,
                                        height: newH
                                    )
                                }
                                .onEnded { _ in
                                    resizeStartRect = nil
                                }
                        )
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Packs `text` into whole-word lines (never splitting a word) and computes the optimal
    /// uniform font size that fits both horizontally and vertically inside `(width, height)`.
    private func layoutMangaText(_ text: String, width: CGFloat, height: CGFloat) -> (lines: [String], fontSize: CGFloat) {
        let usableW = max(24, width - 8)
        let usableH = max(14, height - 4)

        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !words.isEmpty else {
            return (["..."], 10.0)
        }

        let longestWordLen = words.map(\.count).max() ?? 1
        let totalChars = text.count
        let refFont = NSFont.systemFont(ofSize: 10.0, weight: .bold)

        var bestLines: [String] = words
        var bestFontSize: CGFloat = 6.0

        let minTarget = max(longestWordLen, 4)
        let maxTarget = max(minTarget, min(totalChars, 28))

        for targetCols in minTarget...maxTarget {
            var candidateLines: [String] = []
            var currentLine = ""

            for word in words {
                if currentLine.isEmpty {
                    currentLine = word
                } else if currentLine.count + 1 + word.count <= targetCols {
                    currentLine += " " + word
                } else {
                    candidateLines.append(currentLine)
                    currentLine = word
                }
            }
            if !currentLine.isEmpty {
                candidateLines.append(currentLine)
            }

            // Measure widest line at 10pt reference font
            var maxLineWidthAt10: CGFloat = 1.0
            for line in candidateLines {
                let measured = (line as NSString).size(withAttributes: [.font: refFont]).width
                if measured > maxLineWidthAt10 {
                    maxLineWidthAt10 = measured
                }
            }

            // Add 6% safety margin for rounded design glyph width
            let safeWidthAt10 = maxLineWidthAt10 * 1.06
            let totalHeightAt10 = CGFloat(candidateLines.count) * 12.2

            let maxFontW = 10.0 * (usableW / max(safeWidthAt10, 1.0))
            let maxFontH = 10.0 * (usableH / max(totalHeightAt10, 1.0))
            let candidateFontSize = min(maxFontW, maxFontH)

            if candidateFontSize > bestFontSize {
                bestFontSize = candidateFontSize
                bestLines = candidateLines
            }
        }

        let clampedFont = min(max(bestFontSize, 6.0), 22.0)
        return (bestLines, clampedFont)
    }
}
