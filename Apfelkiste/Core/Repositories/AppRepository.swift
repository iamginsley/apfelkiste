import Foundation

/// Everything the UI needs about installed apps. The live version reads the disk, the demo version returns samples.
protocol AppRepository: Sendable {
    /// All apps with metadata, sizes still `nil`.
    func loadApps() async -> [InstalledApp]
    /// Allocated size of an app bundle or leftover.
    func size(of url: URL) async -> Int64
    /// Leftovers of `app` in ~/Library, with sizes.
    func leftovers(for app: InstalledApp, otherBundleIDs: Set<String>) async -> [Leftover]
    /// Quits the app if needed and moves the bundle and the chosen leftovers to the Trash.
    @MainActor func uninstall(_ app: InstalledApp, leftovers: [Leftover]) async throws
}

struct LocalAppRepository: AppRepository {
    var scanner = AppScanner()
    var finder = LeftoverFinder()

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
            leftover.size = DirectorySize.allocatedSize(of: leftover.url)
            return leftover
        }
    }

    @MainActor
    func uninstall(_ app: InstalledApp, leftovers: [Leftover]) async throws {
        guard !app.isProtected else { throw Uninstaller.Failure.protected(app.name) }
        if let id = app.bundleID, Uninstaller.isRunning(bundleID: id) {
            try await Uninstaller.quit(bundleID: id, name: app.name)
        }
        try await Uninstaller.moveToTrash([app.url] + leftovers.map(\.url))
    }
}
