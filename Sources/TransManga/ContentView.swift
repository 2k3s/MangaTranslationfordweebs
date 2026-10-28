import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var model = TransMangaModel()
    @ObservedObject private var store = OverlaySelectionStore.shared
    @State private var selectedTab: AppTab = .home
    @Namespace private var tabSlideNamespace

    var body: some View {
        GeometryReader { geo in
            let isHome = (selectedTab == .home)
            let iconSize: CGFloat = isHome ? 230 : 78
            let iconX: CGFloat = isHome ? (geo.size.width / 2) : 83
            let iconY: CGFloat = isHome ? (geo.size.height / 2 - 48) : 51

            ZStack(alignment: .topLeading) {
                MascotPalette.pearlHighlight
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack {
                        if selectedTab == .home {
                            homeTabView.transition(.opacity)
                        } else if selectedTab == .log {
                            logTabView.transition(.opacity)
                        } else {
                            glossaryTabView.transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    ReactiveLiquidGlassBottomBar(
                        selectedTab: $selectedTab,
                        namespace: tabSlideNamespace
                    )
                    .padding(.bottom, 22)
                    .padding(.top, 10)
                }

                mascotArtworkView(size: iconSize)
                    .position(x: iconX, y: iconY)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedTab)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 680, minHeight: 540)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .transMangaTranslate)) { _ in
            if store.isVisible { model.captureAndTranslate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleClickThrough)) { _ in
            if store.isVisible { model.toggleClickThrough() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleAutoWatch)) { _ in
            if store.isVisible { model.toggleAutoWatch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .transMangaToggleCards)) { _ in
            if store.isVisible { model.toggleOverlayCards() }
        }
    }

    @ViewBuilder
    private func mascotArtworkView(size: CGFloat) -> some View {
        if let appIcon = MascotIconLoader.loadAppIcon() {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(
                    color: MascotPalette.deepEyeBlue.opacity(selectedTab == .home ? 0.10 : 0.06),
                    radius: selectedTab == .home ? 16 : 8,
                    x: 0,
                    y: selectedTab == .home ? 8 : 4
                )
        } else {
            Image(systemName: "cat.fill")
                .font(.system(size: size * 0.48))
                .foregroundColor(MascotPalette.deepEyeBlue)
                .frame(width: size, height: size)
        }
    }

    // MARK: - 1. HOME TAB

    private var homeTabView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 18)

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .center, spacing: 110) {
                    Text("Translate (⌃⌥M)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(MascotPalette.graphiteText)

                    Text("Reading Lock (⌃⌥O)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(
                            store.isClickThrough ? MascotPalette.deepEyeBlue : MascotPalette.graphiteText
                        )
                }
                .frame(width: 175)

                Color.clear.frame(width: 230, height: 230)

                VStack(alignment: .center, spacing: 110) {
                    Text("Auto Watch (⌃⌥W)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(
                            store.isAutoWatching ? MascotPalette.deepEyeBlue : MascotPalette.graphiteText
                        )

                    Text("Peek original (⌃⌥H)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(
                            !store.showTranslationCards ? MascotPalette.deepEyeBlue : MascotPalette.graphiteText
                        )
                }
                .frame(width: 175)
            }

            VStack(spacing: 12) {
                OverlayPowerToggle(isOn: $store.isVisible)

                Menu {
                    ForEach(store.availableModels, id: \.self) { modelName in
                        Button {
                            store.selectedModel = modelName
                        } label: {
                            HStack {
                                Text(modelName)
                                if store.selectedModel == modelName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Refresh Installed Models") {
                        Task { await model.refreshOllamaModels() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11, weight: .medium))
                        Text(store.selectedModel)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(MascotPalette.graphiteText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .modifier(SoftClearGlassCapsuleSurface(isInnerField: false))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - 2. LOG TAB

    private var logTabView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Color.clear.frame(width: 78, height: 78)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.leading, 8)

            ZStack {
                ClearGlassPanelContainer()

                if model.blocks.isEmpty {
                    Text("No translations logged yet.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(MascotPalette.graphiteText.opacity(0.75))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(model.blocks) { block in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 14) {
                                        Text("#\(block.index)")
                                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(MascotPalette.deepEyeBlue)
                                            .frame(width: 28, alignment: .leading)
                                            .padding(.top, 3)

                                        VStack(alignment: .leading, spacing: 4) {
                                            TextField(
                                                "English translation",
                                                text: Binding(
                                                    get: { block.englishText },
                                                    set: { updated in
                                                        model.updateBlockEnglishText(id: block.id, newText: updated)
                                                    }
                                                )
                                            )
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(MascotPalette.charcoalInk)

                                            Text(block.japaneseText)
                                                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                                                .foregroundColor(MascotPalette.graphiteText)
                                                .textSelection(.enabled)
                                        }

                                        Spacer()

                                        Button {
                                            model.requestWordBreakdown(for: block.id)
                                        } label: {
                                            HStack(spacing: 4) {
                                                if block.isBreakingDown {
                                                    ProgressView().controlSize(.mini)
                                                } else {
                                                    Image(systemName: "sparkles")
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                Text(block.breakdownText == nil ? "Breakdown" : "Hide")
                                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundColor(MascotPalette.deepEyeBlue)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .modifier(SoftClearGlassCapsuleSurface(isInnerField: true))
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if let breakdown = block.breakdownText {
                                        Text(breakdown)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .foregroundColor(MascotPalette.charcoalInk.opacity(0.88))
                                            .textSelection(.enabled)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(MascotPalette.icePeriwinkle.opacity(0.45))
                                            )
                                            .padding(.leading, 42)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .modifier(SoftClearGlassRowSurface())
                            }
                        }
                        .padding(24)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 36)
    }

    // MARK: - 3. GLOSSARY TAB

    private var glossaryTabView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Color.clear.frame(width: 78, height: 78)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.leading, 8)

            ZStack(alignment: .bottomTrailing) {
                ClearGlassPanelContainer()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($model.glossary) { $entry in
                            HStack(spacing: 12) {
                                TextField("Japanese", text: $entry.japanese)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .foregroundColor(MascotPalette.charcoalInk)
                                    .padding(.horizontal, 16)
                                    .frame(height: 34)
                                    .modifier(SoftClearGlassCapsuleSurface(isInnerField: true))

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(MascotPalette.graphiteText.opacity(0.75))

                                TextField("English", text: $entry.english)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                    .foregroundColor(MascotPalette.charcoalInk)
                                    .padding(.horizontal, 16)
                                    .frame(height: 34)
                                    .modifier(SoftClearGlassCapsuleSurface(isInnerField: true))

                                Button {
                                    model.removeGlossaryEntry(id: entry.id)
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.65))
                                            .frame(width: 26, height: 26)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(MascotPalette.softPeriwinkle.opacity(0.85), lineWidth: 0.9)
                                            )
                                            .shadow(color: MascotPalette.deepEyeBlue.opacity(0.06), radius: 3, x: 0, y: 1)
                                        Text("×")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(MascotPalette.graphiteText)
                                            .offset(y: -0.5)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .modifier(SoftClearGlassCapsuleSurface(isInnerField: false))
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 84)
                }
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))

                LiquidGlassCirclePlusButton {
                    model.addGlossaryEntry()
                }
                .padding(.trailing, 24)
                .padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 36)
    }
}
