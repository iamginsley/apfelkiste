import AppKit
import SwiftUI

// Colors come from the asset catalog and point at macOS system colors, so light, dark and increased contrast
// come for free: .accentColor (system blue), .appleFresh (red), .appleRipening (orange),
// .appleWindfall (brown), .leaf (green). Labels always use system label colors.

extension Font {
    /// Rounded display face, used for large titles and hero amounts only.
    static let crateTitle = Font.system(.title, design: .rounded).weight(.bold)
    static let heroSize = Font.system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
    static let size = Font.body.monospacedDigit()
}

enum Theme {
    static let minTapSize: CGFloat = 44
    static let listIconSize: CGFloat = 20
    static let inspectorIconSize: CGFloat = 96
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

/// "Vor 3 Tagen", "Gestern", or "Nie" for apps that were never opened.
func lastUsedText(_ date: Date?) -> String {
    guard let date else { return String(localized: "Nie") }
    if Calendar.current.isDateInToday(date) { return String(localized: "Heute") }
    return date.formatted(.relative(presentation: .named)).capitalizedSentence
}

private extension String {
    var capitalizedSentence: String { prefix(1).uppercased() + dropFirst() }
}
