import Foundation

/// Installer receipts: which .pkg put an app on the Mac, and what else it installed.
protocol ReceiptReading: Sendable {
    /// IDs of the packages that installed the app at `url`.
    func packages(containing url: URL) -> [String]
    /// Absolute paths of the files (not folders) a package installed.
    func installedFiles(of package: String) -> [URL]
}

/// Reads receipts through `pkgutil`, which needs no admin rights for reading.
struct PackageReceipts: ReceiptReading {
    /// `pkgutil --file-info` finds nothing for app bundles on current macOS, so this checks each
    /// third-party package whose install location could contain the app for the bundle's folder entry.
    func packages(containing url: URL) -> [String] {
        let appPath = url.plainPath
        let candidates = Self.run(["--pkgs"]).split(separator: "\n").map(String.init).filter { !$0.hasPrefix("com.apple.") }
        return candidates.filter { package in
            let root = Self.installRoot(fromPkgInfo: Self.run(["--pkg-info", package]))
            guard let relative = Self.relativePath(of: appPath, in: root) else { return false }
            return Self.run(["--files", package, "--only-dirs"]).split(separator: "\n").contains { $0 == relative }
        }
    }

    func installedFiles(of package: String) -> [URL] {
        let root = Self.installRoot(fromPkgInfo: Self.run(["--pkg-info", package]))
        let files = Self.run(["--files", package, "--only-files"])
        return files.split(separator: "\n").map { root.appending(path: String($0)) }
    }

    /// The app's path relative to a package's install root, as `pkgutil --files` lists it.
    static func relativePath(of path: String, in root: URL) -> String? {
        var rootPath = root.standardizedFileURL.path(percentEncoded: false)
        if !rootPath.hasSuffix("/") { rootPath += "/" }
        guard path.hasPrefix(rootPath), path.count > rootPath.count else { return nil }
        return String(path.dropFirst(rootPath.count))
    }

    /// Volume plus location from `pkgutil --pkg-info`; the file list is relative to it.
    static func installRoot(fromPkgInfo output: String) -> URL {
        var volume = "/", location = ""
        for line in output.split(separator: "\n") {
            if line.hasPrefix("volume: ") { volume = String(line.dropFirst("volume: ".count)) }
            if line.hasPrefix("location: ") { location = String(line.dropFirst("location: ".count)) }
        }
        return URL(filePath: volume).appending(path: location)
    }

    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/pkgutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
