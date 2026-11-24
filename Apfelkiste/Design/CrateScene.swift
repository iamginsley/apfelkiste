import SwiftUI

/// The immersive look: every sidebar section has its own deep gradient that fills the whole window,
/// with soft glows behind the content. Always dark, so white type sits on it at 7:1 or more.
struct CrateScene: Equatable {
    let top: Color
    let bottom: Color
    let glow: Color
    let symbol: String
    let title: LocalizedStringKey
    let tagline: LocalizedStringKey

    init(top: UInt32, bottom: UInt32, glow: UInt32, symbol: String, title: LocalizedStringKey, tagline: LocalizedStringKey) {
        self.top = Color(hex: top)
        self.bottom = Color(hex: bottom)
        self.glow = Color(hex: glow)
        self.symbol = symbol
        self.title = title
        self.tagline = tagline
    }

    static func == (lhs: CrateScene, rhs: CrateScene) -> Bool { lhs.symbol == rhs.symbol && lhs.top == rhs.top }
}

extension AppFilter {
    // White on the lighter (bottom) color of each gradient: green 8.2:1, amber 9.6:1, blue 10.3:1,
    // orange 8.6:1, teal 8.4:1, graphite 12.7:1. Secondary text is white at 80 %, at least 4.5:1 on all.
    var scene: CrateScene {
        switch self {
        case .all:
            CrateScene(top: 0x0B2E23, bottom: 0x0E5A43, glow: 0x4CD48A, symbol: "shippingbox.fill",
                       title: "Deine Kiste", tagline: "Alle Apps auf deinem Mac, frisch sortiert.")
        case .windfall:
            CrateScene(top: 0x2E1606, bottom: 0x6A3810, glow: 0xF0A040, symbol: "leaf.fill",
                       title: "Fallobst", tagline: "Apps, die schon lange keiner mehr angefasst hat.")
        case .source(.appStore):
            CrateScene(top: 0x0A1838, bottom: 0x1A3C88, glow: 0x5AA0FF, symbol: "bag.fill",
                       title: "App Store", tagline: "Gekauft und geladen im Mac App Store.")
        case .source(.homebrew):
            CrateScene(top: 0x331504, bottom: 0x7A3A08, glow: 0xFFB040, symbol: "mug.fill",
                       title: "Homebrew", tagline: "Per Terminal gebraut.")
        case .source(.direct):
            CrateScene(top: 0x0A2630, bottom: 0x0F5560, glow: 0x42D6C8, symbol: "arrow.down.circle.fill",
                       title: "Direkt geladen", tagline: "Aus dem Netz geholt, ohne Store.")
        case .source(.apple):
            CrateScene(top: 0x141418, bottom: 0x32323C, glow: 0x9A9AA8, symbol: "laptopcomputer",
                       title: "Apple", tagline: "Apples eigene Apps in deinem Programme-Ordner.")
        }
    }
}

/// Full-window gradient with two blurred glows. Cross-fades when the section changes.
struct CrateBackground: View {
    let scene: CrateScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LinearGradient(colors: [scene.top, scene.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            if !reduceTransparency {
                Circle()
                    .fill(scene.glow.opacity(0.35))
                    .frame(width: 520, height: 520)
                    .blur(radius: 140)
                    .offset(x: 320, y: -260)
                Circle()
                    .fill(scene.glow.opacity(0.18))
                    .frame(width: 420, height: 420)
                    .blur(radius: 120)
                    .offset(x: -360, y: 300)
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: scene)
    }
}

/// Colored rounded tile with a white symbol, the sidebar's module icons.
struct SceneTile: View {
    let scene: CrateScene
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [scene.glow, scene.bottom], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: scene.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
