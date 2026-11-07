import Foundation

/// One application bundle found on the Mac.
struct InstalledApp: Identifiable, Hashable, Sendable {
    /// The bundle path is unique on disk, bundle IDs are not (two copies of the same app).
    var id: String { url.path(percentEncoded: false) }

    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let source: AppSource
    /// Homebrew cask token, so the uninstall sheet can offer `brew uninstall --cask`.
    let caskToken: String?
    /// Protected by System Integrity Protection (Safari, apps in /System): shown, but cannot be removed.
    let isProtected: Bool
    /// Developer team from the code signature, used to find shared group containers.
    let teamID: String?
    let installDate: Date?
    /// Last sign of use: Spotlight or the app's own files in ~/Library. See `UsageEvidence`.
    var lastUsed: Date?
    /// Running right now: counts as fresh whatever the dates say.
    var isRunning = false
    /// Allocated size of the bundle in bytes. `nil` until measured.
    var size: Int64?

    /// Apple apps in /Applications (Pages, Keynote, …) can be removed; apps in /System cannot.
    var isAppleApp: Bool { bundleID?.hasPrefix("com.apple.") == true }

    func freshness(now: Date = .now, windfallDays: Int = Freshness.defaultWindfallDays) -> Freshness {
        isRunning ? .fresh : Freshness(lastUsed: lastUsed, now: now, windfallDays: windfallDays)
    }
}

/// Where an app came from, like the "Publisher" column in Windows.
enum AppSource: String, CaseIterable, Sendable, Comparable {
    case appStore
    case homebrew
    case apple
    case direct

    var title: String {
        switch self {
        case .appStore: "App Store"
        case .homebrew: "Homebrew"
        case .apple: "Apple"
        case .direct: "Direkt geladen"
        }
    }

    var symbol: String {
        switch self {
        case .appStore: "bag"
        case .homebrew: "mug"
        case .apple: "laptopcomputer"
        case .direct: "arrow.down.circle"
        }
    }

    static func < (lhs: AppSource, rhs: AppSource) -> Bool { lhs.title < rhs.title }
}

/// The signature element: every app is an apple in the crate. Fresh ones were used recently,
/// windfall ("Fallobst") is what has been lying around untouched.
enum Freshness: Int, Sendable, Comparable, CaseIterable {
    case fresh
    case ripening
    case windfall

    static let defaultWindfallDays = 90
    /// Used within this many days counts as fresh.
    static let freshDays = 30

    init(lastUsed: Date?, now: Date, windfallDays: Int) {
        guard let lastUsed else {
            self = .windfall
            return
        }
        let days = Calendar.current.dateComponents([.day], from: lastUsed, to: now).day ?? 0
        if days < min(Self.freshDays, windfallDays) {
            self = .fresh
        } else if days < windfallDays {
            self = .ripening
        } else {
            self = .windfall
        }
    }

    var title: String {
        switch self {
        case .fresh: "Frisch"
        case .ripening: "Reift nach"
        case .windfall: "Fallobst"
        }
    }

    static func < (lhs: Freshness, rhs: Freshness) -> Bool { lhs.rawValue < rhs.rawValue }
}
