import Foundation

/// Finds what an app leaves behind in ~/Library. Only looks, never deletes.
struct LeftoverFinder: Sendable {
    var library: URL = .homeDirectory.appending(path: "Library")

    /// Exact locations named after the bundle ID.
    private static let exactPaths: [(String, String, Leftover.Kind)] = [
        ("Application Support", "", .applicationSupport),
        ("Caches", "", .caches),
        ("Preferences", ".plist", .preferences),
        ("Containers", "", .containers),
        ("Logs", "", .logs),
        ("Saved Application State", ".savedState", .savedState),
        ("HTTPStorages", "", .httpStorage),
        ("HTTPStorages", ".binarycookies", .httpStorage),
        ("WebKit", "", .webKit),
        ("Cookies", ".binarycookies", .cookies),
        ("Application Scripts", "", .applicationScripts),
    ]

    /// Folders searched for entries that start with the bundle ID (helpers, per-host preferences, agents).
    private static let prefixFolders: [(String, Leftover.Kind)] = [
        ("Preferences/ByHost", .preferences),
        ("LaunchAgents", .launchAgents),
        ("Containers", .containers),
        ("Application Scripts", .applicationScripts),
    ]

    /// Folders where vendors often use the plain app name instead of the bundle ID.
    private static let nameFolders: [(String, Leftover.Kind)] = [
        ("Application Support", .applicationSupport),
        ("Caches", .caches),
        ("Logs", .logs),
    ]

    /// - Parameter otherBundleIDs: IDs of the other installed apps, so `com.foo.app` never claims `com.foo.app.pro`.
    func find(for app: InstalledApp, otherBundleIDs: Set<String>, fileManager: FileManager = .default) -> [Leftover] {
        var found: [String: Leftover] = [:]
        func add(_ url: URL, _ kind: Leftover.Kind, _ match: Leftover.Match) {
            let key = url.standardizedFileURL.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: key), found[key]?.match != .bundleID else { return }
            found[key] = Leftover(url: url, kind: kind, match: match)
        }

        if let id = app.bundleID, !id.isEmpty {
            for (folder, suffix, kind) in Self.exactPaths {
                add(library.appending(path: folder).appending(path: id + suffix), kind, .bundleID)
            }
            for (folder, kind) in Self.prefixFolders {
                let dir = library.appending(path: folder)
                for name in entries(of: dir, fileManager: fileManager)
                where Self.belongs(name, to: id, others: otherBundleIDs) {
                    add(dir.appending(path: name), kind, .bundleID)
                }
            }
            let groups = library.appending(path: "Group Containers")
            for name in entries(of: groups, fileManager: fileManager) {
                if name.hasSuffix("." + id) || Self.belongs(name, to: id, others: otherBundleIDs) {
                    add(groups.appending(path: name), .groupContainers, .bundleID)
                } else if let team = app.teamID, !app.isAppleApp, name.hasPrefix(team + ".") {
                    // Shared by every app of the vendor: only offered, never preselected.
                    add(groups.appending(path: name), .groupContainers, .likely)
                }
            }
        }

        if Self.isDistinctiveName(app.name) {
            for (folder, kind) in Self.nameFolders {
                add(library.appending(path: folder).appending(path: app.name), kind, .likely)
            }
        }

        return found.values.sorted { ($0.match == .bundleID ? 0 : 1, $0.kind.title, $0.id) < ($1.match == .bundleID ? 0 : 1, $1.kind.title, $1.id) }
    }

    /// `name` is the bundle ID itself or starts with it plus a dot, and no longer installed ID claims it.
    /// Bundle IDs contain dots, so names are compared on dot boundaries, never by stripping an "extension".
    static func belongs(_ name: String, to id: String, others: Set<String>) -> Bool {
        func named(_ name: String, after id: String) -> Bool { name == id || name.hasPrefix(id + ".") }
        guard named(name, after: id) else { return false }
        return !others.contains { other in
            other != id && other.hasPrefix(id + ".") && named(name, after: other)
        }
    }

    /// Short or generic names ("Mail", "Notes") would match folders of other software.
    static func isDistinctiveName(_ name: String) -> Bool {
        name.count >= 5 && !["Utilities", "Dienstprogramme", "Helper", "Updater"].contains(name)
    }

    private func entries(of dir: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
    }
}
