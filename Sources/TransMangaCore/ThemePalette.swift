import SwiftUI
import AppKit

enum MascotPalette {
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

enum MascotIconLoader {
    static func loadAppIcon() -> NSImage? {
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppIcon.png")
        if FileManager.default.fileExists(atPath: cwdURL.path),
           let img = NSImage(contentsOf: cwdURL) {
            return img
        }
        if let bundleURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: bundleURL) {
            return img
        }
        return NSApp.applicationIconImage
    }
}

struct ReactiveLiquidGlassBottomBar: View {
    @Binding var selectedTab: AppTab
    let namespace: Namespace.ID

    @State private var isHovered = false
    @State private var hoverLocation: CGPoint = CGPoint(x: 98, y: 20)

    private let tabWidth: CGFloat = 62
    private let barHeight: CGFloat = 42

    var body: some View {
        let totalWidth = tabWidth * CGFloat(AppTab.allCases.count) + 10

        ZStack {
            Capsule(style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.72 : 0.45),
                            MascotPalette.pastelSkyBlue.opacity(isHovered ? 0.38 : 0.18),
                            MascotPalette.icePeriwinkle.opacity(0.22)
                        ],
                        center: UnitPoint(
                            x: isHovered ? min(max(hoverLocation.x / totalWidth, 0.1), 0.9) : 0.5,
                            y: isHovered ? min(max(hoverLocation.y / barHeight, 0.15), 0.85) : 0.5
                        ),
                        startRadius: 2,
                        endRadius: 95
                    )
                )
                .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    MascotPalette.pastelSkyBlue.opacity(0.42),
                                    Color.white.opacity(0.82)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(
                    color: MascotPalette.deepEyeBlue.opacity(isHovered ? 0.14 : 0.08),
                    radius: isHovered ? 14 : 10,
                    x: 0,
                    y: 4
                )

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = (selectedTab == tab)
                    ZStack {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.68),
                                            MascotPalette.pastelSkyBlue.opacity(0.42)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.95),
                                                    MascotPalette.pastelSkyBlue.opacity(0.35)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 0.8
                                        )
                                )
                                .shadow(color: MascotPalette.vividIrisBlue.opacity(0.14), radius: 5, x: 0, y: 2)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 3)
                                .matchedGeometryEffect(id: "liquidGlassTabThumb", in: namespace)
                        }

                        Image(systemName: tab.iconName)
                            .font(.system(size: 15.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(
                                isSelected
                                    ? MascotPalette.deepEyeBlue
                                    : MascotPalette.graphiteText.opacity(0.75)
                            )
                    }
                    .frame(width: tabWidth, height: barHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(width: totalWidth, height: barHeight)
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                hoverLocation = pt
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    hoverLocation = value.location
                    isHovered = true
                    let localX = min(max(0, value.location.x - 5), tabWidth * 3)
                    let idx = min(max(Int(localX / tabWidth), 0), AppTab.allCases.count - 1)
                    if let targetTab = AppTab(rawValue: idx), targetTab != selectedTab {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            selectedTab = targetTab
                        }
                    }
                }
                .onEnded { _ in
                    isHovered = false
                }
        )
    }
}

struct ClearGlassPanelContainer: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 42, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.62),
                        MascotPalette.icePeriwinkle.opacity(0.32)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(RoundedRectangle(cornerRadius: 42, style: .continuous).fill(.ultraThinMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                MascotPalette.softPeriwinkle.opacity(0.55),
                                Color.white.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: MascotPalette.deepEyeBlue.opacity(0.06), radius: 16, x: 0, y: 6)
    }
}

struct SoftClearGlassRowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.65),
                                MascotPalette.icePeriwinkle.opacity(0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                MascotPalette.pastelSkyBlue.opacity(0.32)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
            )
    }
}

struct SoftClearGlassCapsuleSurface: ViewModifier {
    let isInnerField: Bool

    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isInnerField
                                ? [Color.white.opacity(0.75), MascotPalette.icePeriwinkle.opacity(0.35)]
                                : [Color.white.opacity(0.45), MascotPalette.icePeriwinkle.opacity(0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                MascotPalette.softPeriwinkle.opacity(isInnerField ? 0.65 : 0.48)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
            )
    }
}

struct OverlayPowerToggle: View {
    @Binding var isOn: Bool
    @State private var isHovered = false
    @State private var hoverLocation: CGPoint = CGPoint(x: 44, y: 18)

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: isOn
                                ? [
                                    Color.white.opacity(0.65),
                                    MascotPalette.pastelSkyBlue.opacity(0.62),
                                    MascotPalette.softCyanGlow.opacity(0.45)
                                ]
                                : [
                                    Color.white.opacity(isHovered ? 0.75 : 0.52),
                                    MascotPalette.icePeriwinkle.opacity(0.38),
                                    MascotPalette.softPeriwinkle.opacity(0.26)
                                ],
                            center: UnitPoint(
                                x: isHovered ? min(max(hoverLocation.x / 86, 0.15), 0.85) : 0.5,
                                y: isHovered ? min(max(hoverLocation.y / 36, 0.15), 0.85) : 0.5
                            ),
                            startRadius: 2,
                            endRadius: 52
                        )
                    )
                    .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.95),
                                        MascotPalette.pastelSkyBlue.opacity(isOn ? 0.55 : 0.35),
                                        Color.white.opacity(0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    )
                    .shadow(
                        color: MascotPalette.deepEyeBlue.opacity(isOn ? 0.16 : 0.08),
                        radius: isHovered ? 12 : 8,
                        x: 0,
                        y: 4
                    )

                HStack {
                    if isOn {
                        Text("ON")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(MascotPalette.deepEyeBlue)
                            .padding(.leading, 14)
                        Spacer()
                        softGlassThumb.padding(.trailing, 4)
                    } else {
                        softGlassThumb.padding(.leading, 4)
                        Spacer()
                        Text("OFF")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(MascotPalette.graphiteText.opacity(0.8))
                            .padding(.trailing, 12)
                    }
                }
            }
            .frame(width: 86, height: 36)
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                hoverLocation = pt
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
    }

    private var softGlassThumb: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.95), MascotPalette.icePeriwinkle.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.8))
            .shadow(color: MascotPalette.deepEyeBlue.opacity(0.12), radius: 4, x: 0, y: 1.5)
    }
}

struct LiquidGlassCirclePlusButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @State private var hoverLocation: CGPoint = CGPoint(x: 26, y: 26)

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.82 : 0.58),
                                MascotPalette.pastelSkyBlue.opacity(isHovered ? 0.48 : 0.26),
                                MascotPalette.icePeriwinkle.opacity(0.24)
                            ],
                            center: UnitPoint(
                                x: isHovered ? min(max(hoverLocation.x / 52, 0.2), 0.8) : 0.5,
                                y: isHovered ? min(max(hoverLocation.y / 52, 0.2), 0.8) : 0.75
                            ),
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.95),
                                        MascotPalette.pastelSkyBlue.opacity(0.42),
                                        Color.white.opacity(0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    )

                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundColor(MascotPalette.deepEyeBlue)
            }
            .frame(width: 52, height: 52)
            .shadow(
                color: MascotPalette.deepEyeBlue.opacity(isHovered ? 0.16 : 0.09),
                radius: isHovered ? 12 : 8,
                x: 0,
                y: 4
            )
            .scaleEffect(isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                hoverLocation = pt
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
    }
}
