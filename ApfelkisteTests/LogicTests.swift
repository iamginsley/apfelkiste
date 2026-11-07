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

        let found = LeftoverFinder(library: dir.url).find(for: makeApp(), otherBundleIDs: [])
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

        let found = LeftoverFinder(library: dir.url)
            .find(for: makeApp(), otherBundleIDs: ["de.beispiel.pixel", "de.beispiel.pixel.pro"])
        #expect(found.map(\.url.lastPathComponent) == ["de.beispiel.pixel.plist"])
    }

    @Test func teamGroupContainersAreOnlyOffered() {
        let dir = TempDir()
        dir.folder("Group Containers/TEAM123456.de.beispiel.shared")
        dir.folder("Group Containers/group.de.beispiel.pixel")
        dir.folder("Group Containers/OTHERTEAM.de.beispiel.shared")

        let found = LeftoverFinder(library: dir.url).find(for: makeApp(), otherBundleIDs: [])
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.url.lastPathComponent, $0.isPreselected) })
        #expect(byName == ["TEAM123456.de.beispiel.shared": false, "group.de.beispiel.pixel": true])
    }

    @Test func nameMatchesNeedADistinctiveName() {
        let dir = TempDir()
        dir.folder("Application Support/Pixelmeister")
        dir.folder("Application Support/Mail")

        let pixel = LeftoverFinder(library: dir.url).find(for: makeApp(), otherBundleIDs: [])
        #expect(pixel.map(\.match) == [.likely])
        let mail = LeftoverFinder(library: dir.url).find(for: makeApp(name: "Mail", bundleID: "x.mail"), otherBundleIDs: [])
        #expect(mail.isEmpty)
    }

    @Test func belongsNeedsADotBoundary() {
        #expect(LeftoverFinder.belongs("com.foo.app.plist", to: "com.foo.app", others: []))
        #expect(LeftoverFinder.belongs("com.foo.app", to: "com.foo.app", others: []))
        #expect(!LeftoverFinder.belongs("com.foo.application", to: "com.foo.app", others: []))
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
