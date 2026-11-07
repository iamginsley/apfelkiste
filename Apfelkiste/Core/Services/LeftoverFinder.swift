import Foundation

/// Finds what an app leaves behind in ~/Library, /Library, launchd and installer receipts. Only looks, never deletes.
struct LeftoverFinder: Sendable {
    var library: URL = .homeDirectory.appending(path: "Library")
    var systemLibrary: URL = URL(filePath: "/Library")
    var receipts: any ReceiptReading = PackageReceipts()
    /// Whether the current user can move an item without the admin password.
    var isRemovableByUser: @Sendable (URL) -> Bool = LeftoverFinder.isRemovableByUser

    /// Exact locations named after the bundle ID. `systemToo` also checks the same folder in /Library.
    private static let exactPaths: [(String, String, Leftover.Kind, systemToo: Bool)] = [
        ("Application Support", "", .applicationSupport, true),
        ("Caches", "", .caches, true),
        ("Preferences", ".plist", .preferences, true),
        ("Containers", "", .containers, false),
        ("Logs", "", .logs, true),
        ("Saved Application State", ".savedState", .savedState, false),
        ("HTTPStorages", "", .httpStorage, false),
        ("HTTPStorages", ".binarycookies", .httpStorage, false),
        ("WebKit", "", .webKit, false),
        ("Cookies", ".binarycookies", .cookies, false),
        ("Application Scripts", "", .applicationScripts, false),
    ]

    /// Folders searched for entries that start with the bundle ID (helpers, per-host preferences).
    private static let prefixFolders: [(String, Leftover.Kind, systemToo: Bool)] = [
        ("Preferences/ByHost", .preferences, false),
        ("Containers", .containers, false),
        ("Application Scripts", .applicationScripts, false),
        ("PrivilegedHelperTools", .privilegedHelper, true),
    ]

    /// Folders where vendors often use the plain app name instead of the bundle ID.
    private static let nameFolders: [(String, Leftover.Kind)] = [
        ("Application Support", .applicationSupport),
        ("Caches", .caches),
        ("Logs", .logs),
    ]

    /// Installer files outside these places are offered; inside them they might be shared with the system.
    private static let protectedInstallPrefixes = ["/System/", "/usr/lib/", "/usr/bin/", "/usr/sbin/", "/bin/", "/sbin/",
                                                   "/private/var/db/", "/var/db/", "/Applications/"]
    static let maxInstalledFiles = 40

    /// - Parameter otherBundleIDs: IDs of the other installed apps, so `com.foo.app` never claims `com.foo.app.pro`.
    func find(for app: InstalledApp, otherBundleIDs: Set<String>, fileManager: FileManager = .default) -> [Leftover] {
        var found: [String: Leftover] = [:]
        func add(_ leftover: Leftover) {
            var leftover = leftover
            let key = leftover.id
            guard leftover.isReceipt || fileManager.fileExists(atPath: key) else { return }
            if let existing = found[key], existing.match == .bundleID || leftover.match == .likely { return }
            if !leftover.isReceipt { leftover.requiresAdmin = !isRemovableByUser(leftover.url) }
            found[key] = leftover
        }
        func add(_ url: URL, _ kind: Leftover.Kind, _ match: Leftover.Match) {
            add(Leftover(url: url, kind: kind, match: match))
        }

        if let id = app.bundleID, !id.isEmpty {
            for (folder, suffix, kind, systemToo) in Self.exactPaths {
                for lib in libraries(systemToo) {
                    add(lib.appending(path: folder).appending(path: id + suffix), kind, .bundleID)
                }
            }
            for (folder, kind, systemToo) in Self.prefixFolders {
                for lib in libraries(systemToo) {
                    let dir = lib.appending(path: folder)
                    for name in entries(of: dir, fileManager: fileManager)
                    where Self.belongs(name, to: id, others: otherBundleIDs) {
                        add(dir.appending(path: name), kind, .bundleID)
                    }
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

        for job in launchdJobs(for: app, otherBundleIDs: otherBundleIDs, fileManager: fileManager) {
            add(job.leftover)
            if let helper = job.helper { add(helper, .privilegedHelper, .bundleID) }
        }

        if Self.isDistinctiveName(app.name) {
            for (folder, kind) in Self.nameFolders {
                for lib in libraries(true) {
                    add(lib.appending(path: folder).appending(path: app.name), kind, .likely)
                }
            }
        }

        for package in receipts.packages(containing: app.url) {
            add(Leftover(url: URL(filePath: "/var/db/receipts/\(package).plist"), kind: .receipt, match: .bundleID,
                         requiresAdmin: true, packageID: package))
            let appPath = app.url.plainPath
            let files = receipts.installedFiles(of: package).filter { file in
                let path = file.path(percentEncoded: false)
                return !path.hasPrefix(appPath + "/")
                    && !Self.protectedInstallPrefixes.contains { path.hasPrefix($0) }
                    && found.keys.allSatisfy { !path.hasPrefix($0 + "/") }
            }
            for file in files.prefix(Self.maxInstalledFiles) {
                add(file, .installedFile, .likely)
            }
        }

        return found.values.sorted {
            ($0.match == .bundleID ? 0 : 1, $0.requiresAdmin ? 1 : 0, $0.kind.title, $0.id)
                < ($1.match == .bundleID ? 0 : 1, $1.requiresAdmin ? 1 : 0, $1.kind.title, $1.id)
        }
    }

    // MARK: launchd

    struct LaunchdJob {
        let leftover: Leftover
        /// The privileged helper binary the job runs, if it lives in PrivilegedHelperTools.
        let helper: URL?
    }

    /// Launch agents and daemons that belong to the app: named after it, associated with its bundle ID,
    /// or running a program from inside its bundle.
    func launchdJobs(for app: InstalledApp, otherBundleIDs: Set<String>, fileManager: FileManager = .default) -> [LaunchdJob] {
        let folders: [(URL, Leftover.Kind)] = [
            (library.appending(path: "LaunchAgents"), .launchAgents),
            (systemLibrary.appending(path: "LaunchAgents"), .launchAgents),
            (systemLibrary.appending(path: "LaunchDaemons"), .launchDaemons),
        ]
        let appPath = app.url.plainPath
        var jobs: [LaunchdJob] = []
        for (dir, kind) in folders {
            for name in entries(of: dir, fileManager: fileManager) where name.hasSuffix(".plist") {
                let url = dir.appending(path: name)
                let plist = (try? Data(contentsOf: url))
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
                let label = plist["Label"] as? String ?? String(name.dropLast(".plist".count))
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                let associated = plist["AssociatedBundleIdentifiers"] as? [String] ?? []

                var belongs = false
                if let id = app.bundleID {
                    belongs = Self.belongs(label, to: id, others: otherBundleIDs) || associated.contains(id)
                }
                if let program, program.hasPrefix(appPath + "/") { belongs = true }
                guard belongs else { continue }

                let helper = program.map { URL(filePath: $0) }.flatMap { url in
                    url.deletingLastPathComponent().lastPathComponent == "PrivilegedHelperTools" ? url : nil
                }
                jobs.append(LaunchdJob(leftover: Leftover(url: url, kind: kind, match: .bundleID, launchdLabel: label), helper: helper))
            }
        }
        return jobs
    }

    // MARK: Helpers

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

    /// Moving needs write access to the parent folder, and for folders to the folder itself.
    /// In the home folder, ownership decides: privacy-protected folders (Group Containers, other apps'
    /// containers) report as not writable, but Finder can trash them after macOS asks, and root couldn't either.
    @Sendable static func isRemovableByUser(_ url: URL) -> Bool {
        let fm = FileManager.default
        let path = url.path(percentEncoded: false)
        if path.hasPrefix(URL.homeDirectory.path(percentEncoded: false)) {
            let owner = (try? fm.attributesOfItem(atPath: path))?[.ownerAccountID] as? NSNumber
            return owner.map { $0.uint32Value == getuid() } ?? true
        }
        guard fm.isWritableFile(atPath: url.deletingLastPathComponent().path(percentEncoded: false)) else { return false }
        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDirectory)
        return !isDirectory.boolValue || fm.isWritableFile(atPath: path)
    }

    private func libraries(_ systemToo: Bool) -> [URL] { systemToo ? [library, systemLibrary] : [library] }

    private func entries(of dir: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
    }
}

extension URL {
    /// The path without percent encoding and without the trailing slash folder URLs carry.
    var plainPath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
