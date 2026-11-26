import AppKit

/// Full Disk Access lets Apfelkiste see and move what macOS protects from other apps: their containers,
/// Safari data, Mail. There is no API to ask for it; the user turns it on in System Settings.
enum FullDiskAccess {
    /// The user's privacy database can only be opened with Full Disk Access. Opening it also lists
    /// Apfelkiste in System Settings, so the user only has to flip the switch.
    static func isGranted(home: URL = .homeDirectory) -> Bool {
        let path = home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path(percentEncoded: false)
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
