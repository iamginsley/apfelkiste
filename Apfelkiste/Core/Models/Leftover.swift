import Foundation

/// Something an app leaves behind when only the .app is deleted: files in ~/Library or /Library,
/// background services, or the receipt of a .pkg installer.
struct Leftover: Identifiable, Hashable, Sendable {
    var id: String { url.path(percentEncoded: false) }

    let url: URL
    let kind: Kind
    /// How sure we are that it belongs to the app. Only sure matches are preselected.
    let match: Match
    /// Lives outside the home folder or belongs to root: removing it needs the admin password.
    var requiresAdmin = false
    /// For launch agents and daemons: the job label, so the service can be stopped before removal.
    var launchdLabel: String?
    /// For installer receipts: the package ID that `pkgutil --forget` removes.
    var packageID: String?
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
        case launchDaemons
        case privilegedHelper
        case applicationScripts
        case receipt
        case installedFile

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
            case .launchDaemons: "Systemdienst"
            case .privilegedHelper: "Hilfsprogramm mit Admin-Rechten"
            case .applicationScripts: "Skripte"
            case .receipt: "Installationsbeleg"
            case .installedFile: "Vom Installer abgelegt"
            }
        }
    }

    enum Match: Sendable {
        /// Named after the bundle ID or tied to the app by its definition: belongs to this app.
        case bundleID
        /// Named after the app or team, or put there by its installer: probably belongs to it, but check.
        case likely
    }

    var isPreselected: Bool { match == .bundleID }

    /// Receipts are not files to move: `pkgutil --forget` removes them.
    var isReceipt: Bool { packageID != nil }
}
