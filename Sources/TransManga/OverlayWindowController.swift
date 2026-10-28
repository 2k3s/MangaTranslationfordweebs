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

// MARK: - Shared Mascot Palette for the Overlay Controls

private enum OverlayMascotPalette {
    static let pearlHighlight = Color(red: 0.965, green: 0.965, blue: 0.973) // #F6F6F8
    static let icePeriwinkle  = Color(red: 0.906, green: 0.925, blue: 0.965) // #E7ECF6
    static let softPeriwinkle = Color(red: 0.855, green: 0.882, blue: 0.941) // #DAE1F0
    static let pastelSkyBlue  = Color(red: 0.718, green: 0.867, blue: 0.969) // #B7DDF7
    static let softCyanGlow   = Color(red: 0.671, green: 0.831, blue: 0.937) // #ABD4EF
    static let vividIrisBlue  = Color(red: 0.408, green: 0.718, blue: 0.933) // #68B7EE
    static let deepEyeBlue    = Color(red: 0.255, green: 0.467, blue: 0.643) // #4177A4
    static let charcoalInk    = Color(red: 0.188, green: 0.227, blue: 0.267) // #303A44
    static let graphiteText   = Color(red: 0.392, green: 0.427, blue: 0.475) // #646D79
}

final class OverlaySelectionStore: ObservableObject {
    static let shared = OverlaySelectionStore()

    @Published var normalizedSelection = CGRect(x: 0.15, y: 0.15, width: 0.55, height: 0.65)
    @Published var isClickThrough = false
    @Published var showTranslationCards = true
    @Published var isVisible = false
    @Published var isAutoWatching = false
    @Published var isManualSubSelectMode = false
    @Published var overlayWindowID: CGWindowID = kCGNullWindowID
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
        if panel.windowNumber > 0 {
            store.overlayWindowID = CGWindowID(panel.windowNumber)
        }
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
    @State private var isCornerMenuExpanded = false

    var body: some View {
        GeometryReader { geo in
            let rect = store.normalizedSelection
            let boxX = rect.minX * geo.size.width
            let boxY = rect.minY * geo.size.height
            let boxWidth = max(120, rect.width * geo.size.width)
            let boxHeight = max(120, rect.height * geo.size.height)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // Region outline
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            store.isClickThrough
                                ? OverlayMascotPalette.deepEyeBlue.opacity(0.35)
                                : (store.isManualSubSelectMode
                                    ? OverlayMascotPalette.vividIrisBlue.opacity(0.95)
                                    : OverlayMascotPalette.pastelSkyBlue.opacity(0.95)),
                            style: StrokeStyle(
                                lineWidth: store.isClickThrough ? 1.4 : 2.2,
                                dash: store.isClickThrough ? [8, 6] : (store.isManualSubSelectMode ? [6, 4] : [])
                            )
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(store.isClickThrough ? 0.0 : 0.012))
                        )

                    // Translated Speech Bubbles (tight per-line masks + tight text fit inside the original bubble)
                    if store.showTranslationCards {
                        ForEach(store.overlayBoxes) { box in
                            let cx = box.centerX * boxWidth
                            let cy = box.centerY * boxHeight
                            let rawW = max(22, box.orientedWidth * boxWidth)
                            let rawH = max(18, box.orientedHeight * boxHeight)

                            // Keep the English text strictly within the original text bounds
                            // so it never overflows the curved edges of the speech bubble
                            let textFrameW = box.isManualSelection ? rawW : max(rawW + 2, 34)
                            let textFrameH = box.isManualSelection ? rawH : max(rawH + 2, 18)

                            let layout = layoutMangaText(
                                box.text.uppercased(),
                                width: textFrameW,
                                height: textFrameH
                            )

                            ZStack {
                                // 1. Tight per-line masks that erase only the original Japanese glyphs
                                ForEach(box.lineMasks) { mask in
                                    let pad: CGFloat = box.isManualSelection ? 0 : 3
                                    let mW = max(8, mask.width * boxWidth + pad)
                                    let mH = max(8, mask.height * boxHeight + pad)
                                    RoundedRectangle(cornerRadius: min(mW, mH) * 0.22, style: .continuous)
                                        .fill(mask.backgroundColor)
                                        .frame(width: mW, height: mH)
                                        .rotationEffect(.radians(mask.rotationRadians))
                                        .position(
                                            x: mask.centerX * boxWidth,
                                            y: mask.centerY * boxHeight
                                        )
                                }

                                // 2. English text with background hugging ONLY the rendered lines (not a big outer rectangle)
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
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(box.backgroundColor)
                                    )
                                    .frame(width: textFrameW, height: textFrameH, alignment: .center)

                                    if !store.isClickThrough {
                                        Button {
                                            store.removeBox(id: box.id)
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(OverlayMascotPalette.pearlHighlight)
                                                    .frame(width: 16, height: 16)
                                                    .overlay(
                                                        Circle()
                                                            .strokeBorder(OverlayMascotPalette.deepEyeBlue.opacity(0.45), lineWidth: 0.9)
                                                    )
                                                Text("×")
                                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                                    .foregroundColor(OverlayMascotPalette.charcoalInk)
                                                    .offset(y: -0.5)
                                            }
                                            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 4, y: -4)
                                    }
                                }
                                .rotationEffect(.radians(box.rotationRadians))
                                .position(x: cx, y: cy)
                            }
                        }
                    }

                    // Live manual selection box while dragging with Pencil active
                    if let start = manualStartLocal, let current = manualCurrentLocal {
                        let minX = min(start.x, current.x)
                        let minY = min(start.y, current.y)
                        let w = max(4, abs(current.x - start.x))
                        let h = max(4, abs(current.y - start.y))

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                OverlayMascotPalette.vividIrisBlue,
                                style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(OverlayMascotPalette.pastelSkyBlue.opacity(0.22))
                            )
                            .frame(width: w, height: h)
                            .position(x: minX + w / 2, y: minY + h / 2)
                    }

                    // Inside Top-Right Expanding Liquid Glass Control (only when NOT in click-through mode)
                    if !store.isClickThrough {
                        HStack {
                            Spacer()
                            ExpandingTopRightOverlayMenu(
                                isExpanded: $isCornerMenuExpanded,
                                store: store
                            )
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 12)
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

                // Bottom-right resize handle
                if !store.isClickThrough {
                    Circle()
                        .fill(OverlayMascotPalette.pastelSkyBlue)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
                        .shadow(color: OverlayMascotPalette.deepEyeBlue.opacity(0.25), radius: 4, y: 2)
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
        let usableW = max(18, width - 6)
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

        let clampedFont = min(max(bestFontSize, 5.5), 18.0)
        return (bestLines, clampedFont)
    }
}

// MARK: - Inside Top-Right Expanding Liquid Glass Pill (`...` -> `[ ✏️ | Auto - あ | あ | 🔒 ]`)

struct ExpandingTopRightOverlayMenu: View {
    @Binding var isExpanded: Bool
    @ObservedObject var store: OverlaySelectionStore
    @State private var translateFlash = false
    @State private var lockFlash = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OverlayMascotPalette.pearlHighlight.opacity(0.82),
                            OverlayMascotPalette.icePeriwinkle.opacity(0.68),
                            OverlayMascotPalette.pastelSkyBlue.opacity(0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    OverlayMascotPalette.pastelSkyBlue.opacity(0.50),
                                    Color.white.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: OverlayMascotPalette.deepEyeBlue.opacity(0.14), radius: 10, x: 0, y: 4)

            if isExpanded {
                HStack(spacing: 6) {
                    // 1. Pencil: Draw Manual Box
                    OverlayPillItemButton(
                        isActive: store.isManualSubSelectMode,
                        action: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                store.isManualSubSelectMode.toggle()
                            }
                        }
                    ) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13.5, weight: .semibold))
                    }

                    // 2. Auto - あ: Automatic Translation
                    OverlayPillItemButton(
                        isActive: store.isAutoWatching,
                        action: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                store.onToggleAutoWatch?()
                            }
                        }
                    ) {
                        Text("Auto - あ")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    }

                    // 3. あ: Translate Now
                    OverlayPillItemButton(
                        isActive: translateFlash,
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                translateFlash = true
                            }
                            store.onTranslateRequested?()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    translateFlash = false
                                }
                            }
                        }
                    ) {
                        Text("あ")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }

                    // 4. Lock: Click-Through Mode
                    OverlayPillItemButton(
                        isActive: lockFlash,
                        action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                lockFlash = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                lockFlash = false
                                isExpanded = false
                                store.isManualSubSelectMode = false
                                store.onToggleClickThrough?()
                            }
                        }
                    ) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    // Collapse button back into '...'
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(OverlayMascotPalette.graphiteText.opacity(0.75))
                            .frame(width: 20, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            } else {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        isExpanded = true
                    }
                } label: {
                    Text("...")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(OverlayMascotPalette.charcoalInk)
                        .offset(y: -2)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(width: isExpanded ? 242 : 36, height: 36)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: isExpanded)
    }
}

private struct OverlayPillItemButton<Label: View>: View {
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isPressed = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                isPressed = true
            }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeOut(duration: 0.16)) {
                    isPressed = false
                }
            }
        } label: {
            label()
                .foregroundColor(
                    (isActive || isPressed)
                        ? OverlayMascotPalette.deepEyeBlue
                        : OverlayMascotPalette.charcoalInk
                )
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            (isActive || isPressed)
                                ? LinearGradient(
                                    colors: [
                                        OverlayMascotPalette.pastelSkyBlue.opacity(0.85),
                                        OverlayMascotPalette.softCyanGlow.opacity(0.65)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.42),
                                        OverlayMascotPalette.icePeriwinkle.opacity(0.22)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            (isActive || isPressed)
                                ? OverlayMascotPalette.vividIrisBlue.opacity(0.55)
                                : Color.white.opacity(0.65),
                            lineWidth: 0.8
                        )
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
