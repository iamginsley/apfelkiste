import CoreServices
import Foundation
import Security

/// Finds application bundles and reads their metadata. Pure file system work, safe off the main actor.
struct AppScanner: Sendable {
    var roots: [URL] = [
        URL(filePath: "/Applications"),
        URL.homeDirectory.appending(path: "Applications"),
    ]

    /// Apps whose bundle path resolves into these folders are protected by SIP.
    static let protectedPrefixes = ["/System/", "/Library/Apple/"]
    static let protectedBundleIDs: Set<String> = ["com.apple.Safari"]

    func scan(casks: [String: String], fileManager: FileManager = .default) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for url in bundleURLs(fileManager: fileManager) {
            let resolved = url.resolvingSymlinksInPath().path(percentEncoded: false)
            guard seen.insert(resolved).inserted, let app = Self.read(appAt: url, casks: casks) else { continue }
            apps.append(app)
        }
        return apps
    }

    /// `.app` bundles in the roots and one folder level below (e.g. /Applications/Utilities, vendor folders).
    func bundleURLs(fileManager: FileManager = .default) -> [URL] {
        var result: [URL] = []
        for root in roots {
            for item in children(of: root, fileManager: fileManager) {
                if item.pathExtension == "app" {
                    result.append(item)
                } else if isFolder(item) {
                    result += children(of: item, fileManager: fileManager).filter { $0.pathExtension == "app" }
                }
            }
        }
        return result
    }

    static func read(appAt url: URL, casks: [String: String]) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let info = bundle.infoDictionary else { return nil }
        let bundleID = bundle.bundleIdentifier
        let fileName = url.lastPathComponent
        let resolved = url.resolvingSymlinksInPath().path(percentEncoded: false)
        let isProtected = protectedPrefixes.contains { resolved.hasPrefix($0) }
            || bundleID.map(protectedBundleIDs.contains) == true

        let source: AppSource
        if FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false)) {
            source = .appStore
        } else if casks[fileName] != nil {
            source = .homebrew
        } else if bundleID?.hasPrefix("com.apple.") == true {
            source = .apple
        } else {
            source = .direct
        }

        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return InstalledApp(
            url: url,
            name: FileManager.default.displayName(atPath: url.path(percentEncoded: false)),
            bundleID: bundleID,
            version: (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String),
            source: source,
            caskToken: casks[fileName],
            isProtected: isProtected,
            teamID: teamIdentifier(of: url),
            installDate: values?.addedToDirectoryDate ?? values?.creationDate,
            lastUsed: UsageEvidence.lastActivity(appURL: url, bundleID: bundleID),
            size: nil
        )
    }

    static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func children(of url: URL, fileManager: FileManager) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                              options: [.skipsHiddenFiles])) ?? []
    }

    private func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}
