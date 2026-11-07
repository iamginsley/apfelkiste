import Foundation

/// A file or folder in ~/Library that belongs to an app and stays behind when only the .app is deleted.
struct Leftover: Identifiable, Hashable, Sendable {
    var id: String { url.path(percentEncoded: false) }

    let url: URL
    let kind: Kind
    /// How sure we are that it belongs to the app. Only exact bundle ID matches are preselected.
    let match: Match
    var size: Int64?

    enum Kind: String, CaseIterable, Sendable {
        case applicationSupport
        case caches
        case preferences
        case containers
        case groupContainers
        case logs
        case savedState
        case httpStorage
        case webKit
        case cookies
        case launchAgents
        case applicationScripts

        var title: String {
            switch self {
            case .applicationSupport: "Programmdaten"
            case .caches: "Cache"
            case .preferences: "Einstellungen"
            case .containers: "Container"
            case .groupContainers: "Gemeinsamer Container"
            case .logs: "Protokolle"
            case .savedState: "Fensterzustand"
            case .httpStorage, .webKit, .cookies: "Webdaten"
            case .launchAgents: "Hintergrunddienst"
            case .applicationScripts: "Skripte"
            }
        }
    }

    enum Match: Sendable {
        /// Named after the bundle ID: belongs to this app.
        case bundleID
        /// Named after the app or team: probably belongs to it, but check.
        case likely
    }

    var isPreselected: Bool { match == .bundleID }
}
