import AppKit
import SwiftUI

// Colors come from the asset catalog. The accent is Apfelgrün, the app's own note instead of system blue:
// #2E7D32 in light mode (white labels on it 5.1:1, on white 5.1:1), #33853A in dark mode (white labels 4.6:1).
// The apple colors point at macOS system colors, so increased contrast comes for free: .appleFresh (red),
// .appleRipening (orange), .appleWindfall (brown), .leaf (green). Labels always use system label colors.

extension Font {
    /// Rounded display face, used for large titles and hero amounts only.
    static let crateTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let crateHeadline = Font.system(.title2, design: .rounded).weight(.bold)
    static let heroSize = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
    static let size = Font.body.monospacedDigit()
}

enum Theme {
    static let minTapSize: CGFloat = 44
    static let listIconSize: CGFloat = 20
    static let inspectorIconSize: CGFloat = 96
}

extension AppSource {
    /// Fixed colors for the sidebar, used sparingly so each source is recognizable at a glance (sidebars.md).
    var tint: Color {
        switch self {
        case .appStore: .blue
        case .homebrew: .orange
        case .direct: .accentColor
        case .apple: .secondary
        }
    }
}

extension Int64 {
    /// "1,2 GB", like Finder.
    var fileSize: String { formatted(.byteCount(style: .file)) }
}

extension Freshness {
    var color: Color {
        switch self {
        case .fresh: .appleFresh
        case .ripening: .appleRipening
        case .windfall: .appleWindfall
        }
    }
}

/// "Läuft gerade", "Vor 3 Tagen", "Gestern", or "Keine Spur" when nothing shows the app was ever used.
func lastUsedText(_ app: InstalledApp) -> String {
    if app.isRunning { return String(localized: "Läuft gerade") }
    guard let date = app.lastUsed else { return String(localized: "Keine Spur") }
    if Calendar.current.isDateInToday(date) { return String(localized: "Heute") }
    return date.formatted(.relative(presentation: .named)).capitalizedSentence
}

private extension String {
    var capitalizedSentence: String { prefix(1).uppercased() + dropFirst() }
}
