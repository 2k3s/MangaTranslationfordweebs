import Foundation
import AppKit
import SwiftUI

@MainActor
final class TransMangaModel: ObservableObject {
    @Published var blocks: [RecognizedBlock] = []
    @Published var statusMessage = "Flip ON to show the translation box, then press ⌃⌥M."
    @Published var isBusy = false
    @Published var lastCapturedImage: NSImage?
    @Published var isAutoWatching = false
    @Published var isOllamaOnline = false
    @Published var glossary: [GlossaryEntry] = [] {
        didSet { saveGlossary() }
    }

    let store = OverlaySelectionStore.shared

    private let screenCaptureService: ScreenCapturing
    private let ocrService: OCRRecognizing
    private let translationService: MangaTranslating
    private let daemonManager: OllamaDaemonManaging
    private let snapshotExporter: SnapshotExporting

    private var bubbleCache: [String: String] = [:]
    private var recentContext: [(japanese: String, english: String)] = []
    private var watchTimer: Timer?
    private var lastVisualFingerprint: [UInt8]?
    private var pendingStableTicks = 0
    private var lastTranslatedFingerprint: [UInt8]?
    private var activeTranslationTask: Task<Void, Never>?
    private(set) var captureGeneration: UInt64 = 0
    private let glossaryStorageKey = "TransManga.Glossary.v1"

    init(
        screenCaptureService: ScreenCapturing = CoreGraphicsScreenCaptureService(),
        ocrService: OCRRecognizing = VisionKitMangaOCRService(),
        translationService: MangaTranslating = OllamaTranslationService(),
        daemonManager: OllamaDaemonManaging = OllamaDaemonManager(),
        snapshotExporter: SnapshotExporting? = nil,
        autoBootstrap: Bool = true
    ) {
        self.screenCaptureService = screenCaptureService
        self.ocrService = ocrService
        self.translationService = translationService
        self.daemonManager = daemonManager
        self.snapshotExporter = snapshotExporter ?? MangaSnapshotExporter()

        loadGlossary()
        bindOverlayStoreCallbacks()

        if autoBootstrap {
            Task {
                await bootstrapOllamaAndModels()
            }
        }
    }

    private func bindOverlayStoreCallbacks() {
        store.onTranslateRequested = { [weak self] in
            Task { @MainActor in self?.captureAndTranslate() }
        }
        store.onToggleAutoWatch = { [weak self] in
            Task { @MainActor in self?.toggleAutoWatch() }
        }
        store.onToggleClickThrough = { [weak self] in
            Task { @MainActor in self?.toggleClickThrough() }
        }
        store.onManualSubBoxSelected = { [weak self] normSubRect in
            Task { @MainActor in self?.translateManualSubRegion(normSubRect) }
        }
        store.onRemoveBox = { [weak self] id in
            self?.blocks.removeAll { $0.id == id }
        }
        store.onRefreshModelsRequested = { [weak self] in
            Task { @MainActor in await self?.bootstrapOllamaAndModels() }
        }
        store.onSnapshotRequested = { [weak self] in
            Task { @MainActor in self?.exportTranslatedSnapshot() }
        }
        store.onOverlayVisibilityChanged = { [weak self] visible in
            if !visible {
                self?.cancelActiveTranslation()
            }
        }
    }

    func cancelActiveTranslation() {
        captureGeneration &+= 1
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        isBusy = false
    }

    func exportTranslatedSnapshot() {
        guard let captureRect = currentCaptureRect(),
              let cgImage = screenCaptureService.captureRegion(
                  captureRect,
                  belowWindowID: store.overlayWindowID
              ) else {
            statusMessage = "Failed to capture region for snapshot."
            return
        }

        if let savedURL = snapshotExporter.exportSnapshot(
            baseCGImage: cgImage,
            boxes: store.overlayBoxes,
            displaySize: captureRect.size
        ) {
            statusMessage = "Copied snapshot to Clipboard & saved \(savedURL.lastPathComponent) to Downloads!"
        } else {
            statusMessage = "Snapshot export failed."
        }
    }

    func bootstrapOllamaAndModels() async {
        let ready = await daemonManager.ensureServerRunning()
        isOllamaOnline = ready
        if ready {
            await refreshOllamaModels()
        } else {
            statusMessage = "Ollama not found. Install Ollama to translate locally."
        }
    }

    func refreshOllamaModels() async {
        let models = await translationService.fetchInstalledModels()
        store.availableModels = models
        if !models.contains(store.selectedModel), let first = models.first {
            store.selectedModel = first
        }
    }

    func updateBlockEnglishText(id: UUID, newText: String) {
        if let idx = blocks.firstIndex(where: { $0.id == id }) {
            blocks[idx].englishText = newText
            bubbleCache[blocks[idx].japaneseText] = newText
        }
        store.updateBoxText(id: id, newText: newText)
    }

    func requestWordBreakdown(for blockID: UUID) {
        guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        if blocks[idx].breakdownText != nil {
            blocks[idx].breakdownText = nil
            return
        }
        guard !blocks[idx].isBreakingDown else { return }
        blocks[idx].isBreakingDown = true
        let jpText = blocks[idx].japaneseText
        let chosenModel = store.selectedModel

        Task {
            _ = await daemonManager.ensureServerRunning()
            let breakdown = await translationService.explainJapaneseBreakdown(jpText, model: chosenModel)
            if let currentIdx = blocks.firstIndex(where: { $0.id == blockID }) {
                blocks[currentIdx].breakdownText = breakdown
                blocks[currentIdx].isBreakingDown = false
            }
        }
    }

    private func appendToRollingContext(japanese: String, english: String) {
        guard !japanese.isEmpty, !english.isEmpty, english != "..." else { return }
        if let existingIdx = recentContext.firstIndex(where: { $0.japanese == japanese }) {
            recentContext.remove(at: existingIdx)
        }
        recentContext.append((japanese: japanese, english: english))
        if recentContext.count > 6 {
            recentContext.removeFirst(recentContext.count - 6)
        }
    }

    func addGlossaryEntry() {
        glossary.append(GlossaryEntry(japanese: "", english: ""))
    }

    func removeGlossaryEntry(id: UUID) {
        glossary.removeAll { $0.id == id }
        bubbleCache.removeAll()
    }

    private func loadGlossary() {
        guard let data = UserDefaults.standard.data(forKey: glossaryStorageKey),
              let decoded = try? JSONDecoder().decode([GlossaryEntry].self, from: data) else {
            return
        }
        glossary = decoded
    }

    private func saveGlossary() {
        if let encoded = try? JSONEncoder().encode(glossary) {
            UserDefaults.standard.set(encoded, forKey: glossaryStorageKey)
        }
    }

    func toggleClickThrough() {
        store.isClickThrough.toggle()
        statusMessage = store.isClickThrough
            ? "Reading mode locked (click-through ON). Press ⌃⌥O to edit box."
            : "Edit mode active. Drag or resize the box."
    }

    func toggleOverlayCards() {
        store.showTranslationCards.toggle()
        statusMessage = store.showTranslationCards
            ? "Showing English overlay bubbles."
            : "Peeking at original Japanese page (⌃⌥H to show English)."
    }

    func toggleAutoWatch() {
        isAutoWatching.toggle()
        store.isAutoWatching = isAutoWatching

        if isAutoWatching {
            statusMessage = "Auto-Watch ON (⌃⌥W): scrolling or turning pages will auto-translate."
            startAutoWatchLoop()
        } else {
            statusMessage = "Auto-Watch paused."
            stopAutoWatchLoop()
        }
    }

    private func startAutoWatchLoop() {
        stopAutoWatchLoop()
        pendingStableTicks = 0
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkScreenForChanges()
            }
        }
    }

    private func stopAutoWatchLoop() {
        watchTimer?.invalidate()
        watchTimer = nil
    }

    private func currentCaptureRect() -> CGRect? {
        guard let screen = NSScreen.main else { return nil }
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

    private func checkScreenForChanges() {
        guard isAutoWatching, store.isVisible else { return }
        guard let captureRect = currentCaptureRect() else { return }

        guard let cgImage = screenCaptureService.captureRegion(
            captureRect,
            belowWindowID: store.overlayWindowID
        ) else {
            return
        }

        let currentFP = screenCaptureService.computeFingerprint(for: cgImage)

        if let lastFP = lastVisualFingerprint {
            let diff = screenCaptureService.fingerprintDifference(lastFP, currentFP)
            if diff > 0.025 {
                // Page scrolled or changed: cancel any in-flight translation from the old page immediately
                if isBusy {
                    cancelActiveTranslation()
                }
                lastVisualFingerprint = currentFP
                pendingStableTicks = 1
                store.overlayBoxes = []
                return
            }
        } else {
            lastVisualFingerprint = currentFP
            pendingStableTicks = 1
            return
        }

        guard !isBusy else { return }

        if pendingStableTicks > 0 {
            pendingStableTicks += 1
            if pendingStableTicks >= 2 {
                pendingStableTicks = 0
                if let lastTranslated = lastTranslatedFingerprint,
                   screenCaptureService.fingerprintDifference(lastTranslated, currentFP) <= 0.020 {
                    return
                }
                lastTranslatedFingerprint = currentFP
                captureAndTranslate()
            }
        }
    }

    func captureAndTranslate() {
        guard store.isVisible else {
            statusMessage = "Turn ON the translation box first."
            return
        }
        guard let captureRect = currentCaptureRect() else {
            statusMessage = "Unable to determine screen capture region."
            return
        }

        cancelActiveTranslation()
        let generation = captureGeneration
        isBusy = true
        statusMessage = "Capturing selected region..."

        activeTranslationTask = Task {
            defer {
                if self.captureGeneration == generation {
                    self.isBusy = false
                }
            }

            if !isOllamaOnline {
                isOllamaOnline = await daemonManager.ensureServerRunning()
            }
            guard !Task.isCancelled, self.captureGeneration == generation else { return }

            guard let cgImage = screenCaptureService.captureRegion(
                captureRect,
                belowWindowID: store.overlayWindowID
            ) else {
                statusMessage = "Screen capture failed. Check Screen Recording permission in System Settings."
                return
            }

            let fp = screenCaptureService.computeFingerprint(for: cgImage)
            lastVisualFingerprint = fp
            lastTranslatedFingerprint = fp
            lastCapturedImage = NSImage(cgImage: cgImage, size: captureRect.size)

            do {
                statusMessage = "Detecting Japanese speech bubbles..."
                var detectedBlocks = try await ocrService.recognizeBubbleClusters(from: cgImage)
                guard !Task.isCancelled, self.captureGeneration == generation else { return }

                if detectedBlocks.isEmpty {
                    blocks = []
                    store.overlayBoxes = []
                    statusMessage = "No Japanese text detected in the selected area."
                    return
                }

                var appearances: [(bg: Color, fg: Color)] = []
                for i in 0..<detectedBlocks.count {
                    let bubbleColor = screenCaptureService.sampleBubbleAppearance(
                        in: cgImage,
                        normalizedBox: detectedBlocks[i].boundingBox
                    )
                    appearances.append(bubbleColor)

                    for mIdx in 0..<detectedBlocks[i].lineMasks.count {
                        let lineSample = screenCaptureService.sampleBubbleAppearance(
                            in: cgImage,
                            normalizedBox: detectedBlocks[i].lineMasks[mIdx].sampleBox
                        )
                        detectedBlocks[i].lineMasks[mIdx].backgroundColor = lineSample.bg
                    }
                }

                var uncachedIndices: [Int] = []
                var uncachedJapanese: [String] = []

                for (i, block) in detectedBlocks.enumerated() {
                    if let cachedEnglish = bubbleCache[block.japaneseText] {
                        detectedBlocks[i].englishText = cachedEnglish
                    } else {
                        uncachedIndices.append(i)
                        uncachedJapanese.append(block.japaneseText)
                    }
                }

                blocks = detectedBlocks

                if !uncachedJapanese.isEmpty {
                    statusMessage = "Translating \(uncachedJapanese.count) bubble(s) with \(store.selectedModel)..."
                    let freshTranslations = try await translationService.translateBubbles(
                        uncachedJapanese,
                        model: store.selectedModel,
                        glossary: glossary,
                        recentContext: recentContext
                    )
                    guard !Task.isCancelled, self.captureGeneration == generation else { return }

                    for (offset, blockIdx) in uncachedIndices.enumerated() where offset < freshTranslations.count {
                        let english = freshTranslations[offset]
                        detectedBlocks[blockIdx].englishText = english
                        if english != "..." {
                            bubbleCache[detectedBlocks[blockIdx].japaneseText] = english
                        }
                    }
                }

                for block in detectedBlocks {
                    appendToRollingContext(japanese: block.japaneseText, english: block.englishText)
                }

                blocks = detectedBlocks
                store.overlayBoxes = detectedBlocks.enumerated().map { i, block in
                    OverlayTranslationBox(
                        id: block.id,
                        index: block.index,
                        text: block.englishText,
                        boundingBox: block.boundingBox,
                        centerX: block.centerX,
                        centerY: block.centerY,
                        orientedWidth: block.orientedWidth,
                        orientedHeight: block.orientedHeight,
                        rotationRadians: block.rotationRadians,
                        lineMasks: block.lineMasks,
                        backgroundColor: appearances[i].bg,
                        textColor: appearances[i].fg,
                        isManualSelection: false
                    )
                }
                store.showTranslationCards = true
                statusMessage = "Translated \(detectedBlocks.count) speech bubble(s)."
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.captureGeneration == generation else { return }
                statusMessage = error.localizedDescription
            }
        }
    }

    func translateManualSubRegion(_ normSubRect: CGRect) {
        guard !isBusy else { return }
        guard let fullCaptureRect = currentCaptureRect() else { return }

        let generation = captureGeneration
        isBusy = true
        statusMessage = "Translating manually selected box..."

        activeTranslationTask = Task {
            defer {
                if self.captureGeneration == generation {
                    self.isBusy = false
                }
            }

            if !isOllamaOnline {
                isOllamaOnline = await daemonManager.ensureServerRunning()
            }
            guard !Task.isCancelled, self.captureGeneration == generation else { return }

            guard let fullCGImage = screenCaptureService.captureRegion(
                fullCaptureRect,
                belowWindowID: store.overlayWindowID
            ) else {
                statusMessage = "Screen capture failed."
                return
            }

            let imgW = CGFloat(fullCGImage.width)
            let imgH = CGFloat(fullCGImage.height)
            let cropRect = CGRect(
                x: max(0, normSubRect.minX * imgW),
                y: max(0, normSubRect.minY * imgH),
                width: min(imgW - max(0, normSubRect.minX * imgW), max(8, normSubRect.width * imgW)),
                height: min(imgH - max(0, normSubRect.minY * imgH), max(8, normSubRect.height * imgH))
            ).integral

            guard let subCGImage = fullCGImage.cropping(to: cropRect) else {
                statusMessage = "Manual selection was too small."
                return
            }

            do {
                let subClusters = try await ocrService.recognizeBubbleClusters(from: subCGImage)
                guard !Task.isCancelled, self.captureGeneration == generation else { return }

                let combinedJP = subClusters
                    .map(\.japaneseText)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !combinedJP.isEmpty else {
                    statusMessage = "No Japanese text detected inside the manual box."
                    return
                }

                let english: String
                if let cached = bubbleCache[combinedJP] {
                    english = cached
                } else {
                    let translated = try await translationService.translateBubbles(
                        [combinedJP],
                        model: store.selectedModel,
                        glossary: glossary,
                        recentContext: recentContext
                    )
                    guard !Task.isCancelled, self.captureGeneration == generation else { return }
                    english = translated.first ?? "..."
                    if english != "..." {
                        bubbleCache[combinedJP] = english
                    }
                }

                appendToRollingContext(japanese: combinedJP, english: english)

                let appearance = screenCaptureService.sampleBubbleAppearance(
                    in: fullCGImage,
                    normalizedBox: normSubRect
                )
                let nextIndex = (store.overlayBoxes.map(\.index).max() ?? 0) + 1
                let sharedID = UUID()

                let manualMask = OrientedLineMask(
                    centerX: normSubRect.midX,
                    centerY: normSubRect.midY,
                    width: normSubRect.width,
                    height: normSubRect.height,
                    rotationRadians: 0,
                    sampleBox: normSubRect,
                    backgroundColor: appearance.bg
                )

                let newBox = OverlayTranslationBox(
                    id: sharedID,
                    index: nextIndex,
                    text: english,
                    boundingBox: normSubRect,
                    centerX: normSubRect.midX,
                    centerY: normSubRect.midY,
                    orientedWidth: normSubRect.width,
                    orientedHeight: normSubRect.height,
                    rotationRadians: 0,
                    lineMasks: [manualMask],
                    backgroundColor: appearance.bg,
                    textColor: appearance.fg,
                    isManualSelection: true
                )

                let newBlock = RecognizedBlock(
                    id: sharedID,
                    index: nextIndex,
                    japaneseText: combinedJP,
                    englishText: english,
                    boundingBox: normSubRect,
                    centerX: normSubRect.midX,
                    centerY: normSubRect.midY,
                    orientedWidth: normSubRect.width,
                    orientedHeight: normSubRect.height,
                    rotationRadians: 0,
                    lineMasks: [manualMask]
                )

                blocks.append(newBlock)
                store.overlayBoxes.append(newBox)
                store.showTranslationCards = true
                statusMessage = "Added manual translation #\(nextIndex)."
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.captureGeneration == generation else { return }
                statusMessage = error.localizedDescription
            }
        }
    }
}
