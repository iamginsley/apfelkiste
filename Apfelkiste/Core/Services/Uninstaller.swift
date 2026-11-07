import AppKit

/// Quits apps and moves them with their leftovers to the Trash. Nothing is deleted permanently,
/// so every uninstall can be undone from the Trash.
@MainActor
enum Uninstaller {
    enum Failure: LocalizedError {
        case stillRunning(String)
        case protected(String)

        var errorDescription: String? {
            switch self {
            case .stillRunning(let name): "\(name) lässt sich nicht beenden. Beende die App selbst und versuch es noch einmal."
            case .protected(let name): "\(name) gehört zu macOS und kann nicht entfernt werden."
            }
        }
    }

    static func isRunning(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Asks the app to quit and waits up to `timeout` for it.
    static func quit(bundleID: String, name: String, timeout: Duration = .seconds(8)) async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        let deadline = ContinuousClock.now + timeout
        while running.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else { throw Failure.stillRunning(name) }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Moves the items to the Trash through Finder, which asks for an admin password when needed
    /// (App Store apps belong to root). Returns the items that ended up in the Trash.
    @discardableResult
    static func moveToTrash(_ urls: [URL]) async throws -> [URL] {
        guard !urls.isEmpty else { return [] }
        let moved = try await NSWorkspace.shared.recycle(urls)
        return Array(moved.keys)
    }
}
