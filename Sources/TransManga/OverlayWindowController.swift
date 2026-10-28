import SwiftUI
import AppKit
import Combine

struct OrientedLineMask: Identifiable {
    let id = UUID()
    let centerX: CGFloat
    let centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotationRadians: Double
    let sampleBox: CGRect
    var backgroundColor: Color = .white
}

struct OverlayTranslationBox: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
    let boundingBox: CGRect
    let centerX: CGFloat
    let centerY: CGFloat
    let orientedWidth: CGFloat
    let orientedHeight: CGFloat
    let rotationRadians: Double
    let lineMasks: [OrientedLineMask]
    let backgroundColor: Color
    let textColor: Color
    var isManualSelection: Bool = false
}

final class OverlaySelectionStore: ObservableObject {
    static let shared = OverlaySelectionStore()

    @Published var normalizedSelection = CGRect(x: 0.15, y: 0.15, width: 0.55, height: 0.65)
    @Published var isClickThrough = false
    @Published var showTranslationCards = true
    /// Starts OFF when the app opens
    @Published var isVisible = false
    @Published var isAutoWatching = false
    @Published var isManualSubSelectMode = false
    @Published var overlayBoxes: [OverlayTranslationBox] = []

    var onTranslateRequested: (() -> Void)?
    var onToggleAutoWatch: (() -> Void)?
    var onToggleClickThrough: (() -> Void)?
    var onManualSubBoxSelected: ((CGRect) -> Void)?
    var onRemoveBox: ((UUID) -> Void)?

    private init() {}

    func removeBox(id: UUID) {
        overlayBoxes.removeAll { $0.id == id }
        onRemoveBox?(id)
    }
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

        store.$isVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                guard let self = self else { return }
                if visible {
                    self.presentPanel()
                } else {
                    self.panel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    private func presentPanel() {
        if panel == nil {
            createPanel()
        }
        guard let panel = panel else { return }
        if let screen = NSScreen.main {
            panel.setFrame(screen.frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    func showOverlay() {
        store.isVisible = true
    }

    func hideOverlay() {
        store.isVisible = false
    }

    func toggleOverlay() {
        store.isVisible.toggle()
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
        store.isVisible = visible
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
    @State private var manualStartLocal: CGPoint? = nil
    @State private var manualCurrentLocal: CGPoint? = nil

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
                                : (store.isManualSubSelectMode ? Color.yellow.opacity(0.95) : Color.cyan.opacity(0.95)),
                            style: StrokeStyle(
                                lineWidth: store.isClickThrough ? 1.5 : 2.5,
                                dash: store.isClickThrough ? [8, 6] : (store.isManualSubSelectMode ? [6, 4] : [])
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
                            let rawW = max(24, box.orientedWidth * boxWidth)
                            let rawH = max(18, box.orientedHeight * boxHeight)

                            let isVerticalColumn = !box.isManualSelection
                                && rawH > rawW * 1.15
                                && abs(box.rotationRadians) < 0.05
                            let textFrameW = box.isManualSelection
                                ? rawW
                                : (isVerticalColumn ? min(max(rawW * 1.35, 74), rawW + 34) : max(rawW + 8, 44))
                            let textFrameH = box.isManualSelection
                                ? rawH
                                : max(rawH + 8, 22)

                            let layout = layoutMangaText(
                                box.text.uppercased(),
                                width: textFrameW,
                                height: textFrameH
                            )

                            ZStack {
                                ForEach(box.lineMasks) { mask in
                                    let pad: CGFloat = box.isManualSelection ? 0 : 10
                                    let mW = max(12, mask.width * boxWidth + pad)
                                    let mH = max(12, mask.height * boxHeight + pad)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(mask.backgroundColor)
                                        .frame(width: mW, height: mH)
                                        .rotationEffect(.radians(mask.rotationRadians))
                                        .position(
                                            x: mask.centerX * boxWidth,
                                            y: mask.centerY * boxHeight
                                        )
                                }

                                ZStack(alignment: .topTrailing) {
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
                                    .padding(.horizontal, box.isManualSelection ? 2 : 4)
                                    .padding(.vertical, box.isManualSelection ? 1 : 2)
                                    .frame(width: textFrameW, height: textFrameH, alignment: .center)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(box.backgroundColor)
                                    )

                                    if !store.isClickThrough {
                                        Button {
                                            store.removeBox(id: box.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white, Color.red.opacity(0.9))
                                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 7, y: -7)
                                    }
                                }
                                .rotationEffect(.radians(box.rotationRadians))
                                .position(x: cx, y: cy)
                            }
                        }
                    }

                    if let start = manualStartLocal, let current = manualCurrentLocal {
                        let minX = min(start.x, current.x)
                        let minY = min(start.y, current.y)
                        let w = max(4, abs(current.x - start.x))
                        let h = max(4, abs(current.y - start.y))

                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                Color.yellow,
                                style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.yellow.opacity(0.16))
                            )
                            .frame(width: w, height: h)
                            .position(x: minX + w / 2, y: minY + h / 2)
                    }
                }
                .frame(width: boxWidth, height: boxHeight)
                .position(x: boxX + boxWidth / 2, y: boxY + boxHeight / 2)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("overlayRoot"))
                        .onChanged { value in
                            guard !store.isClickThrough else { return }

                            if store.isManualSubSelectMode {
                                let startLocal = CGPoint(
                                    x: min(max(0, value.startLocation.x - boxX), boxWidth),
                                    y: min(max(0, value.startLocation.y - boxY), boxHeight)
                                )
                                let currLocal = CGPoint(
                                    x: min(max(0, value.location.x - boxX), boxWidth),
                                    y: min(max(0, value.location.y - boxY), boxHeight)
                                )
                                if manualStartLocal == nil {
                                    manualStartLocal = startLocal
                                }
                                manualCurrentLocal = currLocal
                            } else {
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
                        }
                        .onEnded { _ in
                            if store.isManualSubSelectMode {
                                if let start = manualStartLocal, let end = manualCurrentLocal {
                                    let minX = min(start.x, end.x)
                                    let minY = min(start.y, end.y)
                                    let w = abs(end.x - start.x)
                                    let h = abs(end.y - start.y)

                                    if w >= 12 && h >= 12 {
                                        let normSubRect = CGRect(
                                            x: minX / boxWidth,
                                            y: minY / boxHeight,
                                            width: w / boxWidth,
                                            height: h / boxHeight
                                        )
                                        store.onManualSubBoxSelected?(normSubRect)
                                    }
                                }
                                manualStartLocal = nil
                                manualCurrentLocal = nil
                            } else {
                                dragStartRect = nil
                            }
                        }
                )

                // Top floating toolbar
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(store.isClickThrough ? Color.green : (store.isManualSubSelectMode ? Color.yellow : Color.cyan))
                            .frame(width: 8, height: 8)
                        Text(
                            store.isClickThrough
                                ? "Reading (⌃⌥O)"
                                : (store.isManualSubSelectMode ? "Drag Over Missed Text" : "Region Edit")
                        )
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }

                    if !store.isClickThrough {
                        Button("Translate (⌃⌥M)") {
                            store.onTranslateRequested?()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .controlSize(.small)

                        Button(store.isManualSubSelectMode ? "Done Drawing" : "+ Draw Box") {
                            store.isManualSubSelectMode.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(store.isManualSubSelectMode ? .yellow : .orange)
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
                            store.isManualSubSelectMode = false
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
            .coordinateSpace(name: "overlayRoot")
        }
        .ignoresSafeArea()
    }

    private func layoutMangaText(_ text: String, width: CGFloat, height: CGFloat) -> (lines: [String], fontSize: CGFloat) {
        let usableW = max(20, width - 6)
        let usableH = max(12, height - 4)

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
        var bestFontSize: CGFloat = 5.5

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

            var maxLineWidthAt10: CGFloat = 1.0
            for line in candidateLines {
                let measured = (line as NSString).size(withAttributes: [.font: refFont]).width
                if measured > maxLineWidthAt10 {
                    maxLineWidthAt10 = measured
                }
            }

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

        let clampedFont = min(max(bestFontSize, 5.5), 22.0)
        return (bestLines, clampedFont)
    }
}
