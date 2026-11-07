import AppKit

/// What an uninstall does, worked out before anything is touched. Pure, so it can be tested.
struct UninstallPlan: Equatable {
    /// Moved to the Trash through Finder, no password.
    var userTrash: [URL] = []
    /// Moved to the Trash by the admin script (root-owned or outside the home folder).
    var adminTrash: [URL] = []
    /// Jobs in the user's GUI domain (launch agents), stopped without a password.
    var agentLabels: [String] = []
    /// System daemons, stopped by the admin script.
    var daemonLabels: [String] = []
    /// Installer receipts, forgotten by the admin script.
    var packageIDs: [String] = []

    init(app: InstalledApp, appRequiresAdmin: Bool, leftovers: [Leftover]) {
        if appRequiresAdmin { adminTrash.append(app.url) } else { userTrash.append(app.url) }
        for leftover in leftovers {
            if let package = leftover.packageID {
                packageIDs.append(package)
                continue
            }
            if let label = leftover.launchdLabel {
                if leftover.kind == .launchDaemons { daemonLabels.append(label) } else { agentLabels.append(label) }
            }
            if leftover.requiresAdmin { adminTrash.append(leftover.url) } else { userTrash.append(leftover.url) }
        }
    }

    var needsAdmin: Bool { !adminTrash.isEmpty || !daemonLabels.isEmpty || !packageIDs.isEmpty }

    /// One shell script for everything that needs root, so the password is asked once.
    /// `destinations` maps each admin item to its free name in the user's Trash.
    func adminScript(destinations: [URL: URL]) -> String? {
        guard needsAdmin else { return nil }
        var lines = ["set -e"]
        for label in daemonLabels {
            lines.append("/bin/launchctl bootout system/\(Self.quote(label)) 2>/dev/null || true")
        }
        for url in adminTrash {
            guard let destination = destinations[url] else { continue }
            lines.append("/bin/mv \(Self.quote(url.plainPath)) \(Self.quote(destination.plainPath))")
        }
        for package in packageIDs {
            lines.append("/usr/sbin/pkgutil --forget \(Self.quote(package)) >/dev/null 2>&1 || true")
        }
        return lines.joined(separator: "\n")
    }

    /// Single-quotes a value for /bin/sh.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A free name in `trash` for each item, adding a time like Finder does when the name is taken.
    static func trashDestinations(for urls: [URL], in trash: URL, now: Date = .now,
                                  exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }) -> [URL: URL] {
        var taken = Set<String>()
        var result: [URL: URL] = [:]
        let stamp = now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: ":", with: ".")
        for url in urls {
            let name = url.lastPathComponent
            var candidate = trash.appending(path: name)
            var counter = 1
            while exists(candidate) || taken.contains(candidate.lastPathComponent) {
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                let suffix = counter == 1 ? " \(stamp)" : " \(stamp) \(counter)"
                candidate = trash.appending(path: ext.isEmpty ? base + suffix : "\(base)\(suffix).\(ext)")
                counter += 1
            }
            taken.insert(candidate.lastPathComponent)
            result[url] = candidate
        }
        return result
    }
}

/// Quits apps, stops their services and moves everything to the Trash. Nothing is deleted permanently,
/// so every uninstall can be undone from the Trash (receipts aside, which only matter to the installer).
@MainActor
enum Uninstaller {
    enum Failure: LocalizedError {
        case stillRunning(String)
        case protected(String)
        case cancelled
        case admin(String)

        var errorDescription: String? {
            switch self {
            case .stillRunning(let name): "\(name) lässt sich nicht beenden. Beende die App selbst und versuch es noch einmal."
            case .protected(let name): "\(name) gehört zu macOS und kann nicht entfernt werden."
            case .cancelled: "Abgebrochen. Es wurde nichts entfernt."
            case .admin(let message): "Das Entfernen mit Admin-Rechten hat nicht geklappt: \(message)"
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

    static func run(_ plan: UninstallPlan) async throws {
        // Root work first: if the password prompt is cancelled, nothing has been touched yet.
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        if let script = plan.adminScript(destinations: UninstallPlan.trashDestinations(for: plan.adminTrash, in: trash)) {
            try runAsAdmin(script)
        }
        stopAgents(plan.agentLabels)
        if !plan.userTrash.isEmpty {
            _ = try await NSWorkspace.shared.recycle(plan.userTrash)
        }
    }

    /// Stops launch agents in the user's GUI domain so they don't keep running until the next login.
    private static func stopAgents(_ labels: [String]) {
        for label in labels {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/launchctl")
            process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Runs the script as root after macOS asks for the admin password ("Apfelkiste möchte Änderungen vornehmen").
    private static func runAsAdmin(_ script: String) throws {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"Apfelkiste möchte Reste entfernen, die zum System gehören.\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw Failure.cancelled }
        throw Failure.admin(error[NSAppleScript.errorMessage] as? String ?? "Unbekannter Fehler")
    }
}
