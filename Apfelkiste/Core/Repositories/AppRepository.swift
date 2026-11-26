import Foundation

/// Everything the UI needs about installed apps. The live version reads the disk, the demo version returns samples.
protocol AppRepository: Sendable {
    /// All apps with metadata, sizes still `nil`.
    func loadApps() async -> [InstalledApp]
    /// Allocated size of an app bundle or leftover.
    func size(of url: URL) async -> Int64
    /// Leftovers of `app` in ~/Library, /Library, launchd and installer receipts, with sizes.
    func leftovers(for app: InstalledApp, otherBundleIDs: Set<String>) async -> [Leftover]
    /// Quits the app if needed and moves the bundle and the chosen leftovers to the Trash.
    /// Returns the leftovers that could not be moved; the app itself is gone when this returns.
    @MainActor func uninstall(_ app: InstalledApp, leftovers: [Leftover]) async throws -> [URL]
    /// Quits the app if needed and moves its data to the Trash; the app stays. Returns what could not be moved.
    @MainActor func reset(_ app: InstalledApp, leftovers: [Leftover]) async throws -> [URL]
    /// What apps that are gone left behind, with sizes.
    func orphans(installed: Set<String>) async -> [OrphanGroup]
    /// Moves leftovers of removed apps to the Trash. Returns what could not be moved.
    @MainActor func remove(_ leftovers: [Leftover]) async throws -> [URL]
    /// Whether Apfelkiste may see and move what macOS protects (other apps' containers).
    func hasFullDiskAccess() -> Bool
}

struct LocalAppRepository: AppRepository {
    var scanner = AppScanner()
    var finder = LeftoverFinder()
    var orphanFinder = OrphanFinder()

    @concurrent
    func loadApps() async -> [InstalledApp] {
        scanner.scan(casks: HomebrewCasks.installedApps())
    }

    @concurrent
    func size(of url: URL) async -> Int64 {
        DirectorySize.allocatedSize(of: url)
    }

    @concurrent
    func leftovers(for app: InstalledApp, otherBundleIDs: Set<String>) async -> [Leftover] {
        finder.find(for: app, otherBundleIDs: otherBundleIDs).map { leftover in
            var leftover = leftover
            if !leftover.isReceipt { leftover.size = DirectorySize.allocatedSize(of: leftover.url) }
            return leftover
        }
    }

    @MainActor
    func uninstall(_ app: InstalledApp, leftovers: [Leftover]) async throws -> [URL] {
        guard !app.isProtected else { throw Uninstaller.Failure.protected(app.name) }
        if let id = app.bundleID, Uninstaller.isRunning(bundleID: id) {
            try await Uninstaller.quit(bundleID: id, name: app.name)
        }
        let plan = UninstallPlan(app: app, appRequiresAdmin: !LeftoverFinder.isRemovableByUser(app.url), leftovers: leftovers)
        return try await Uninstaller.run(plan)
    }

    @MainActor
    func reset(_ app: InstalledApp, leftovers: [Leftover]) async throws -> [URL] {
        guard !app.isProtected else { throw Uninstaller.Failure.protected(app.name) }
        if let id = app.bundleID, Uninstaller.isRunning(bundleID: id) {
            try await Uninstaller.quit(bundleID: id, name: app.name)
        }
        return try await Uninstaller.run(UninstallPlan(leftovers: leftovers))
    }

    @concurrent
    func orphans(installed: Set<String>) async -> [OrphanGroup] {
        orphanFinder.find(installed: installed).map { group in
            var group = group
            for index in group.leftovers.indices {
                group.leftovers[index].size = DirectorySize.allocatedSize(of: group.leftovers[index].url)
            }
            return group
        }
    }

    @MainActor
    func remove(_ leftovers: [Leftover]) async throws -> [URL] {
        try await Uninstaller.run(UninstallPlan(leftovers: leftovers))
    }

    func hasFullDiskAccess() -> Bool { FullDiskAccess.isGranted() }
}
