import Foundation
import Testing
@testable import Apfelkiste

/// Uninstalls a throwaway app for real (user-level path, no password). Opt-in:
/// `TEST_RUNNER_REAL_UNINSTALL=1 xcodebuild test … -only-testing:ApfelkisteTests/RealUninstallSmoke`.
@MainActor
struct RealUninstallSmoke {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REAL_UNINSTALL"] != nil))
    func uninstallThrowawayApp() async throws {
        let fm = FileManager.default
        let id = "de.apfelkiste.wegwerf"
        let home = URL.homeDirectory
        let appURL = home.appending(path: "Applications/Apfelkiste Wegwerf.app")
        let cache = home.appending(path: "Library/Caches/\(id)")
        let prefs = home.appending(path: "Library/Preferences/\(id).plist")
        try fm.createDirectory(at: appURL.appending(path: "Contents"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": "Apfelkiste Wegwerf", "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: appURL.appending(path: "Contents/Info.plist"))
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: cache.appending(path: "data"))
        try PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .xml, options: 0).write(to: prefs)

        let repository = LocalAppRepository()
        let app = try #require(AppScanner.read(appAt: appURL, casks: [:]))
        let leftovers = await repository.leftovers(for: app, otherBundleIDs: [])
        print("UNINSTALL: leftovers \(leftovers.map { "\($0.kind.title) admin=\($0.requiresAdmin)" })")
        #expect(Set(leftovers.map(\.url.lastPathComponent)) == [id, "\(id).plist"])
        #expect(leftovers.allSatisfy { !$0.requiresAdmin })

        try await repository.uninstall(app, leftovers: leftovers)

        for url in [appURL, cache, prefs] {
            #expect(!fm.fileExists(atPath: url.path(percentEncoded: false)), "still there: \(url.path)")
        }
        // The items are in the Trash now. The test runner may not read ~/.Trash (privacy protection), so empty it yourself.
    }
}
