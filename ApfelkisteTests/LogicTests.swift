import Foundation
import Testing
@testable import Apfelkiste

private func makeApp(name: String = "Pixelmeister", bundleID: String? = "de.beispiel.pixel", teamID: String? = "TEAM123456",
                     source: AppSource = .direct, lastUsed: Date? = nil) -> InstalledApp {
    InstalledApp(url: URL(filePath: "/Applications/\(name).app"), name: name, bundleID: bundleID, version: "1.0",
                 source: source, caskToken: nil, isProtected: false, teamID: teamID, installDate: nil,
                 lastUsed: lastUsed, size: nil)
}

/// A throwaway folder that is removed when the test ends.
private final class TempDir {
    let url = FileManager.default.temporaryDirectory.appending(path: "apfelkiste-\(UUID().uuidString)")
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ path: String, bytes: Int = 10) -> URL {
        let file = url.appending(path: path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data(count: bytes))
        return file
    }

    func folder(_ path: String) {
        try? FileManager.default.createDirectory(at: url.appending(path: path), withIntermediateDirectories: true)
    }
}

/// A finder that only sees the temp folder: user library at `dir`, system library at `dir/SystemLib`.
private func testFinder(_ dir: TempDir, receipts: any ReceiptReading = FakeReceipts()) -> LeftoverFinder {
    LeftoverFinder(library: dir.url, systemLibrary: dir.url.appending(path: "SystemLib"), receipts: receipts,
                   isRemovableByUser: { !$0.path(percentEncoded: false).contains("/SystemLib/") })
}

private struct FakeReceipts: ReceiptReading {
    var packages: [String: [String]] = [:]
    var files: [String: [URL]] = [:]
    func packages(containing url: URL) -> [String] { packages[url.path(percentEncoded: false)] ?? [] }
    func installedFiles(of package: String) -> [URL] { files[package] ?? [] }
}

private func writePlist(_ dict: [String: Any], to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    try! data.write(to: url)
}

struct FreshnessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func daysAgo(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }

    @Test func neverUsedIsWindfall() {
        #expect(Freshness(lastUsed: nil, now: now, windfallDays: 90) == .windfall)
    }

    @Test(arguments: [(0, Freshness.fresh), (29, .fresh), (30, .ripening), (89, .ripening), (90, .windfall), (400, .windfall)])
    func thresholds(days: Int, expected: Freshness) {
        #expect(Freshness(lastUsed: daysAgo(days), now: now, windfallDays: 90) == expected)
    }

    @Test func shortWindfallSettingWins() {
        // With a 30-day setting there is no ripening phase.
        #expect(Freshness(lastUsed: daysAgo(29), now: now, windfallDays: 30) == .fresh)
        #expect(Freshness(lastUsed: daysAgo(30), now: now, windfallDays: 30) == .windfall)
    }
}

struct LeftoverFinderTests {
    @Test func findsBundleIDLocations() {
        let dir = TempDir()
        dir.folder("Application Support/de.beispiel.pixel")
        dir.file("Caches/de.beispiel.pixel/cache.db", bytes: 100)
        dir.file("Preferences/de.beispiel.pixel.plist")
        dir.file("Preferences/ByHost/de.beispiel.pixel.ABC-123.plist")
        dir.folder("Saved Application State/de.beispiel.pixel.savedState")
        dir.file("LaunchAgents/de.beispiel.pixel.updater.plist")
        dir.folder("Containers/de.beispiel.pixel.helper")
        // Belongs to someone else.
        dir.file("Preferences/de.beispiel.other.plist")

        let found = testFinder(dir).find(for: makeApp(), otherBundleIDs: [])
        let names = Set(found.map(\.url.lastPathComponent))
        #expect(names == ["de.beispiel.pixel", "de.beispiel.pixel.plist", "de.beispiel.pixel.ABC-123.plist",
                          "de.beispiel.pixel.savedState", "de.beispiel.pixel.updater.plist", "de.beispiel.pixel.helper"])
        #expect(found.count == 7) // Application Support and Caches share a name.
        #expect(found.allSatisfy { $0.isPreselected })
    }

    @Test func neverClaimsAnotherInstalledApp() {
        let dir = TempDir()
        dir.file("Preferences/de.beispiel.pixel.plist")
        dir.file("Preferences/ByHost/de.beispiel.pixel.pro.ABC.plist")
        dir.folder("Containers/de.beispiel.pixel.pro")
        dir.folder("Containers/de.beispiel.pixelate")

        let found = testFinder(dir)
            .find(for: makeApp(), otherBundleIDs: ["de.beispiel.pixel", "de.beispiel.pixel.pro"])
        #expect(found.map(\.url.lastPathComponent) == ["de.beispiel.pixel.plist"])
    }

    @Test func teamGroupContainersAreOnlyOffered() {
        let dir = TempDir()
        dir.folder("Group Containers/TEAM123456.de.beispiel.shared")
        dir.folder("Group Containers/group.de.beispiel.pixel")
        dir.folder("Group Containers/OTHERTEAM.de.beispiel.shared")

        let found = testFinder(dir).find(for: makeApp(), otherBundleIDs: [])
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.url.lastPathComponent, $0.isPreselected) })
        #expect(byName == ["TEAM123456.de.beispiel.shared": false, "group.de.beispiel.pixel": true])
    }

    @Test func nameMatchesNeedADistinctiveName() {
        let dir = TempDir()
        dir.folder("Application Support/Pixelmeister")
        dir.folder("Application Support/Mail")

        let pixel = testFinder(dir).find(for: makeApp(), otherBundleIDs: [])
        #expect(pixel.map(\.match) == [.likely])
        let mail = testFinder(dir).find(for: makeApp(name: "Mail", bundleID: "x.mail"), otherBundleIDs: [])
        #expect(mail.isEmpty)
    }

    @Test func belongsNeedsADotBoundary() {
        #expect(LeftoverFinder.belongs("com.foo.app.plist", to: "com.foo.app", others: []))
        #expect(LeftoverFinder.belongs("com.foo.app", to: "com.foo.app", others: []))
        #expect(!LeftoverFinder.belongs("com.foo.application", to: "com.foo.app", others: []))
    }
}

struct SystemLeftoverTests {
    @Test func findsSystemFoldersAsAdmin() {
        let dir = TempDir()
        dir.folder("SystemLib/Application Support/de.beispiel.pixel")
        dir.file("SystemLib/Preferences/de.beispiel.pixel.plist")
        let found = testFinder(dir).find(for: makeApp(), otherBundleIDs: [])
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.requiresAdmin && $0.isPreselected })
    }

    @Test func daemonWithHelperByAssociatedBundleID() {
        let dir = TempDir()
        // Label uses a vendor prefix, not the bundle ID: only AssociatedBundleIdentifiers ties it to the app.
        let helper = dir.file("SystemLib/PrivilegedHelperTools/de.beispiel.tool")
        writePlist(["Label": "de.beispiel.tool", "AssociatedBundleIdentifiers": ["de.beispiel.pixel"],
                    "Program": helper.path(percentEncoded: false)],
                   to: dir.url.appending(path: "SystemLib/LaunchDaemons/de.beispiel.tool.plist"))
        writePlist(["Label": "com.other.daemon", "Program": "/usr/local/bin/other"],
                   to: dir.url.appending(path: "SystemLib/LaunchDaemons/com.other.daemon.plist"))

        let found = testFinder(dir).find(for: makeApp(), otherBundleIDs: [])
        let daemon = try? #require(found.first { $0.kind == .launchDaemons })
        #expect(daemon?.launchdLabel == "de.beispiel.tool")
        #expect(daemon?.requiresAdmin == true)
        #expect(found.contains { $0.kind == .privilegedHelper && $0.url.lastPathComponent == "de.beispiel.tool" })
        #expect(found.count == 2)
    }

    @Test func agentRunningFromInsideTheBundle() {
        let dir = TempDir()
        // Folder URLs from the scanner end in a slash; matching must not depend on it.
        let app = InstalledApp(url: URL(filePath: "/Applications/Pixelmeister.app/", directoryHint: .isDirectory), name: "Pixelmeister",
                               bundleID: "de.beispiel.pixel", version: nil, source: .direct, caskToken: nil, isProtected: false,
                               teamID: nil, installDate: nil, lastUsed: nil, size: nil)
        #expect(app.url.path(percentEncoded: false).hasSuffix("/"))
        writePlist(["Label": "com.vendor.sync", "ProgramArguments": ["/Applications/Pixelmeister.app/Contents/MacOS/sync", "--daemon"]],
                   to: dir.url.appending(path: "LaunchAgents/com.vendor.sync.plist"))
        let found = testFinder(dir).find(for: app, otherBundleIDs: [])
        #expect(found.map(\.launchdLabel) == ["com.vendor.sync"])
        #expect(found.first?.requiresAdmin == false)
    }

    @Test func receiptAndInstalledFiles() {
        let dir = TempDir()
        let tool = dir.file("usr-local/bin/pixel")
        let receipts = FakeReceipts(
            packages: ["/Applications/Pixelmeister.app": ["de.beispiel.pixel.pkg"]],
            files: ["de.beispiel.pixel.pkg": [
                URL(filePath: "/Applications/Pixelmeister.app/Contents/Info.plist"), // inside the app: removed with it
                URL(filePath: "/usr/lib/libshared.dylib"),                         // system place: never offered
                tool,
                dir.url.appending(path: "gone/file"),                                // missing: skipped
            ]])
        let found = testFinder(dir, receipts: receipts).find(for: makeApp(), otherBundleIDs: [])
        let receipt = try? #require(found.first { $0.isReceipt })
        #expect(receipt?.packageID == "de.beispiel.pixel.pkg")
        #expect(receipt?.isPreselected == true)
        let files = found.filter { $0.kind == .installedFile }
        #expect(files.map(\.url) == [tool])
        #expect(files.first?.isPreselected == false)
    }
}

struct UninstallPlanTests {
    @Test func splitsByPrivilege() {
        let app = makeApp()
        let leftovers = [
            Leftover(url: URL(filePath: "/Users/me/Library/Caches/x"), kind: .caches, match: .bundleID),
            Leftover(url: URL(filePath: "/Users/me/Library/LaunchAgents/x.plist"), kind: .launchAgents, match: .bundleID, launchdLabel: "x.agent"),
            Leftover(url: URL(filePath: "/Library/LaunchDaemons/x.plist"), kind: .launchDaemons, match: .bundleID, requiresAdmin: true, launchdLabel: "x.daemon"),
            Leftover(url: URL(filePath: "/var/db/receipts/x.pkg.plist"), kind: .receipt, match: .bundleID, requiresAdmin: true, packageID: "x.pkg"),
        ]
        let plan = UninstallPlan(app: app, appRequiresAdmin: true, leftovers: leftovers)
        #expect(plan.userTrash.map(\.lastPathComponent) == ["x", "x.plist"])
        #expect(plan.adminTrash.map(\.path) == ["/Applications/Pixelmeister.app", "/Library/LaunchDaemons/x.plist"])
        #expect(plan.agentLabels == ["x.agent"])
        #expect(plan.daemonLabels == ["x.daemon"])
        #expect(plan.packageIDs == ["x.pkg"])

        let trash = URL(filePath: "/Users/me/.Trash")
        let script = plan.adminScript(destinations: UninstallPlan.trashDestinations(for: plan.adminTrash, in: trash, exists: { _ in false }))
        #expect(script == """
        set -e
        /bin/launchctl bootout system/'x.daemon' 2>/dev/null || true
        /bin/mv '/Applications/Pixelmeister.app' '/Users/me/.Trash/Pixelmeister.app'
        /bin/mv '/Library/LaunchDaemons/x.plist' '/Users/me/.Trash/x.plist'
        /usr/sbin/pkgutil --forget 'x.pkg' >/dev/null 2>&1 || true
        """)
    }

    @Test func userOnlyPlanNeedsNoScript() {
        let plan = UninstallPlan(app: makeApp(), appRequiresAdmin: false, leftovers: [])
        #expect(!plan.needsAdmin)
        #expect(plan.adminScript(destinations: [:]) == nil)
    }

    @Test func quotesSingleQuotes() {
        #expect(UninstallPlan.quote("Bob's App") == #"'Bob'\''s App'"#)
    }

    @Test func trashNamesAvoidCollisions() {
        let trash = URL(filePath: "/T")
        let urls = [URL(filePath: "/a/Tool.app"), URL(filePath: "/b/Tool.app"), URL(filePath: "/c/notes")]
        let taken: Set<String> = ["/T/Tool.app", "/T/notes"]
        let result = UninstallPlan.trashDestinations(for: urls, in: trash, exists: { taken.contains($0.path) })
        let names = urls.map { result[$0]!.lastPathComponent }
        #expect(Set(names).count == 3)
        #expect(names.allSatisfy { !taken.contains("/T/" + $0) })
        #expect(names[0].hasPrefix("Tool ") && names[0].hasSuffix(".app"))
    }
}

struct PackageReceiptsTests {
    @Test func relativeToInstallRoot() {
        #expect(PackageReceipts.relativePath(of: "/Applications/X.app", in: URL(filePath: "/Applications")) == "X.app")
        #expect(PackageReceipts.relativePath(of: "/Applications/X.app", in: URL(filePath: "/")) == "Applications/X.app")
        #expect(PackageReceipts.relativePath(of: "/Applications/X.app", in: URL(filePath: "/Library")) == nil)
    }

    @Test func parsesInstallRoot() {
        let info = "package-id: com.x.pkg\nversion: 1\nvolume: /\nlocation: Library/X\ninstall-time: 1\n"
        #expect(PackageReceipts.installRoot(fromPkgInfo: info).path == "/Library/X")
    }
}

struct HomebrewCasksTests {
    @Test func readsAppNamesFromJSONAndRuby() {
        let json = #"{"token":"visual-studio-code","artifacts":[{"app":["Visual Studio Code.app"]},{"zap":[]}]}"#
        let ruby = ##"app "Firefox.app"\n  binary "#{appdir}/Firefox.app/Contents/MacOS/firefox""##
        #expect(HomebrewCasks.appNames(inCaskDefinition: json) == ["Visual Studio Code.app"])
        #expect(HomebrewCasks.appNames(inCaskDefinition: ruby) == ["Firefox.app"])
    }

    @Test func mapsAppsToTokens() {
        let dir = TempDir()
        let def = dir.file("iterm2/.metadata/3.5/20260101/Casks/iterm2.json")
        try? #"{"artifacts":[{"app":["iTerm.app"]}]}"#.write(to: def, atomically: true, encoding: .utf8)
        #expect(HomebrewCasks.installedApps(caskrooms: [dir.url]) == ["iTerm.app": "iterm2"])
    }
}

struct DirectorySizeTests {
    @Test func sumsFilesRecursively() {
        let dir = TempDir()
        dir.file("a/one", bytes: 10_000)
        dir.file("a/b/two", bytes: 20_000)
        let size = DirectorySize.allocatedSize(of: dir.url.appending(path: "a"))
        // Allocated size rounds up to blocks.
        #expect(size >= 30_000)
        #expect(size < 60_000)
    }

    @Test func missingItemIsZero() {
        #expect(DirectorySize.allocatedSize(of: URL(filePath: "/nope/\(UUID().uuidString)")) == 0)
    }
}

@MainActor
struct AppsViewModelTests {
    func makeModel() async -> AppsViewModel {
        let defaults = UserDefaults(suiteName: "apfelkiste-tests-\(UUID().uuidString)")!
        let model = AppsViewModel(repository: DemoAppRepository(), defaults: defaults)
        await model.load()
        return model
    }

    @Test func loadsAndMeasuresEveryApp() async {
        let model = await makeModel()
        #expect(model.apps.count == DemoAppRepository.samples.count)
        #expect(model.apps.allSatisfy { $0.size != nil })
        #expect(!model.isMeasuring)
    }

    @Test func filtersBySourceAndWindfall() async {
        let model = await makeModel()
        model.filter = .source(.homebrew)
        #expect(Set(model.visibleApps.map(\.name)) == ["Notizblock", "Kartenhaus"])
        model.filter = .windfall
        #expect(Set(model.visibleApps.map(\.name)) == ["Kartenhaus", "Zeiterfassung", "Vokabeltrainer"])
        model.windfallDays = 365
        #expect(Set(model.visibleApps.map(\.name)) == ["Zeiterfassung", "Vokabeltrainer"])
    }

    @Test func searchesNameAndBundleID() async {
        let model = await makeModel()
        model.searchText = "frosch"
        #expect(model.visibleApps.map(\.name) == ["Wetterfrosch"])
        model.searchText = "de.beispiel.kaffee"
        #expect(model.visibleApps.map(\.name) == ["Kaffeeklatsch"])
    }

    @Test func sortsBySizeDescending() async {
        let model = await makeModel()
        model.sortOrder = [KeyPathComparator(\InstalledApp.sortSize, order: .reverse)]
        #expect(model.visibleApps.first?.name == "Tonstudio")
    }

    @Test func uninstallRemovesFromList() async {
        let model = await makeModel()
        let app = model.apps[0]
        model.selection = [app.id]
        model.requestUninstall()
        #expect(model.uninstallTarget == app)
        model.didUninstall(app)
        #expect(!model.apps.contains(app))
        #expect(model.selection.isEmpty)
    }
}

@MainActor
struct UninstallViewModelTests {
    @Test func preselectsOnlySureLeftovers() async {
        let app = makeApp(name: "Tonstudio", bundleID: "de.beispiel.tonstudio")
        let model = UninstallViewModel(app: app, repository: DemoAppRepository(), otherBundleIDs: [])
        await model.search()
        #expect(model.phase == .ready)
        #expect(model.leftovers.count == 5)
        #expect(model.selectedLeftovers.count == 4)
        #expect(model.canConfirm)
        let confirmed = await model.confirm()
        #expect(confirmed)
        #expect(model.phase == .done)
    }

    @Test func homebrewAppsGetTheBrewCommand() {
        let app = InstalledApp(url: URL(filePath: "/Applications/iTerm.app"), name: "iTerm", bundleID: "com.googlecode.iterm2",
                               version: nil, source: .homebrew, caskToken: "iterm2", isProtected: false, teamID: nil,
                               installDate: nil, lastUsed: nil, size: nil)
        let model = UninstallViewModel(app: app, repository: DemoAppRepository(), otherBundleIDs: [])
        #expect(model.brewCommand == "brew uninstall --cask --zap iterm2")
    }
}
