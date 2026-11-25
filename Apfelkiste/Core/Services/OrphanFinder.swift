import AppKit

/// What apps left behind that are no longer installed, for example because they were dragged to the Trash.
/// Groups everything named after one bundle ID. Only looks, never deletes.
struct OrphanFinder: Sendable {
    var library: URL = .homeDirectory.appending(path: "Library")
    var systemLibrary: URL = URL(filePath: "/Library")
    /// Whether an app with this bundle ID exists anywhere on the Mac (not in the Trash).
    var isInstalledAnywhere: @Sendable (String) -> Bool = OrphanFinder.launchServicesKnows
    var isRemovableByUser: @Sendable (URL) -> Bool = LeftoverFinder.isRemovableByUser

    /// Folders in ~/Library whose entries are named after bundle IDs, with the suffix to strip.
    private static let folders: [(String, String, Leftover.Kind)] = [
        ("Application Support", "", .applicationSupport),
        ("Caches", "", .caches),
        ("Containers", "", .containers),
        ("Preferences", ".plist", .preferences),
        ("Saved Application State", ".savedState", .savedState),
        ("HTTPStorages", ".binarycookies", .httpStorage),
        ("HTTPStorages", "", .httpStorage),
        ("WebKit", "", .webKit),
        ("Logs", "", .logs),
    ]

    /// Shared by every app that bundles the framework (analytics, crash reporters, image caches), not
    /// left behind by one app. Application Scripts is skipped for the same reason: macOS creates empty
    /// script folders for app groups and extensions of apps that are still installed.
    static let sharedPrefixes = [
        "com.amplitude.", "com.bugsnag.", "com.crashlytics.", "com.firebase.", "com.google.gmp.",
        "com.google.firebase.", "com.hackemist.", "com.onevcat.", "com.plausiblelabs.", "com.segment.",
        "com.telemetrydeck.", "io.sentry.", "com.microsoft.shared", "com.microsoft.office", "com.setapp.defaults",
        "group.", "systemgroup.",
        // Command line and developer tools: no app bundle to find, but very much in use.
        "org.swift.", "main.kts.", "org.cups.", "com.android.", "org.python.", "org.nodejs.", "com.docker.",
        "org.gradle.", "org.llvm.", "com.jetbrains.toolbox.", "org.homebrew.",
    ]

    /// Apple apps that come from the App Store and can be deleted. Every other `com.apple.` name belongs
    /// to macOS itself (daemons, system services), which has no app to look for, so it is never offered.
    static let removableAppleApps: Set<String> = [
        "com.apple.garageband10", "com.apple.iMovieApp", "com.apple.iWork.Pages", "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote", "com.apple.dt.Xcode", "com.apple.FinalCut", "com.apple.logic10",
        "com.apple.mainstage3", "com.apple.motionapp", "com.apple.Compressor", "com.apple.configurator.ui",
        "com.apple.TestFlight",
    ]

    /// - Parameter installed: bundle IDs of the apps in the list, checked before asking LaunchServices.
    func find(installed: Set<String>, fileManager: FileManager = .default) -> [OrphanGroup] {
        var byID: [String: [Leftover]] = [:]
        func add(_ id: String, _ leftover: Leftover) {
            var leftover = leftover
            leftover.requiresAdmin = !isRemovableByUser(leftover.url)
            byID[id, default: []].append(leftover)
        }

        for (folder, suffix, kind) in Self.folders {
            let dir = library.appending(path: folder)
            for name in entries(of: dir, fileManager: fileManager) where name.hasSuffix(suffix) {
                let id = String(name.dropLast(suffix.count))
                guard Self.looksLikeBundleID(id), !Self.isShared(id) else { continue }
                let url = dir.appending(path: name)
                // ".binarycookies" and "" both match in HTTPStorages; take each entry once.
                guard !byID.values.contains(where: { $0.contains { $0.url == url } }) else { continue }
                add(id, Leftover(url: url, kind: kind, match: .bundleID))
            }
        }

        // Background services whose program is gone: they fail at every login.
        let launchd: [(URL, Leftover.Kind)] = [
            (library.appending(path: "LaunchAgents"), .launchAgents),
            (systemLibrary.appending(path: "LaunchAgents"), .launchAgents),
            (systemLibrary.appending(path: "LaunchDaemons"), .launchDaemons),
        ]
        for (dir, kind) in launchd {
            for name in entries(of: dir, fileManager: fileManager) where name.hasSuffix(".plist") {
                let url = dir.appending(path: name)
                let plist = (try? Data(contentsOf: url))
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
                let label = plist["Label"] as? String ?? String(name.dropLast(".plist".count))
                guard let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first,
                      program.hasPrefix("/"), !program.hasPrefix("/System/"), !program.hasPrefix("/usr/"),
                      !fileManager.fileExists(atPath: program), Self.looksLikeBundleID(label) else { continue }
                add(label, Leftover(url: url, kind: kind, match: .bundleID, launchdLabel: label))
            }
        }

        let orphanIDs = byID.keys.filter { !isClaimed($0, installed: installed) }
        return Self.group(orphanIDs.map { ($0, byID[$0] ?? []) }).map { group in
            var group = group
            let vendor = Self.vendor(of: group.bundleID)
            group.vendorStillInstalled = installed.contains { Self.vendor(of: $0) == vendor }
            return group
        }
    }

    static func isShared(_ id: String) -> Bool { sharedPrefixes.contains { id.hasPrefix($0) } }

    /// "com.google" from "com.google.Keystone.Agent".
    static func vendor(of id: String) -> String { id.split(separator: ".").prefix(2).joined(separator: ".") }

    /// Belongs to an installed app (itself, a helper or extension of one, or the vendor prefix of one),
    /// or to macOS.
    func isClaimed(_ id: String, installed: Set<String>) -> Bool {
        if id.hasPrefix("com.apple.") {
            return !Self.removableAppleApps.contains { id == $0 || id.hasPrefix($0 + ".") }
                || Self.prefixes(of: id).contains(where: isInstalledAnywhere)
        }
        if installed.contains(where: { $0 == id || id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return true }
        return Self.prefixes(of: id).contains(where: isInstalledAnywhere)
    }

    /// `com.foo.app.helper` → `com.foo.app.helper`, `com.foo.app` (never just `com.foo`).
    static func prefixes(of id: String) -> [String] {
        let parts = id.split(separator: ".")
        guard parts.count >= 3 else { return [id] }
        return (3...parts.count).reversed().map { parts.prefix($0).joined(separator: ".") }
    }

    /// Reverse-DNS with at least three parts, so plain folder names ("Google", "Code") never match.
    static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy(allowed.contains) }
            && parts[0].unicodeScalars.allSatisfy(CharacterSet.letters.contains)
    }

    /// Puts `com.foo.app.helper` under `com.foo.app` when both are orphaned.
    static func group(_ items: [(String, [Leftover])]) -> [OrphanGroup] {
        var groups: [String: [Leftover]] = [:]
        for (id, leftovers) in items.sorted(by: { $0.0.count < $1.0.count }) {
            let owner = groups.keys.filter { id.hasPrefix($0 + ".") }.max(by: { $0.count < $1.count }) ?? id
            groups[owner, default: []].append(contentsOf: leftovers)
        }
        return groups.map { OrphanGroup(bundleID: $0.key, leftovers: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.bundleID.localizedStandardCompare($1.bundleID) == .orderedAscending }
    }

    @Sendable static func launchServicesKnows(_ id: String) -> Bool {
        let trash = URL.homeDirectory.appending(path: ".Trash").plainPath + "/"
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .contains { !$0.plainPath.hasPrefix(trash) && !$0.plainPath.contains("/.Trashes/") }
    }

    private func entries(of dir: URL, fileManager: FileManager) -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []
    }
}

/// Everything one removed app left behind.
struct OrphanGroup: Identifiable, Hashable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    var leftovers: [Leftover]
    /// Another app of the same vendor is installed: this may be its updater or shared data, so it is
    /// pointed out and left out of "select all".
    var vendorStillInstalled = false

    var size: Int64 { leftovers.reduce(0) { $0 + ($1.size ?? 0) } }
    var requiresAdmin: Bool { leftovers.contains(where: \.requiresAdmin) }

    /// "garageband10" from "com.apple.garageband10": a readable hint which app it was.
    var displayName: String {
        let parts = bundleID.split(separator: ".")
        let name = parts.count >= 3 ? parts[2...].joined(separator: ".") : bundleID
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "Container, Einstellungen, Cache"
    var kindsSummary: String {
        var seen: [String] = []
        for title in leftovers.map(\.kind.title) where !seen.contains(title) { seen.append(title) }
        return seen.formatted(.list(type: .and, width: .narrow))
    }
}
