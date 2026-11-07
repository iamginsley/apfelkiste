import AppKit
import Observation

/// Sidebar entries, like the categories in Windows' "Programs and Features".
enum AppFilter: Hashable {
    case all
    case windfall
    case source(AppSource)
}

@Observable
@MainActor
final class AppsViewModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    private(set) var isMeasuring = false

    var filter: AppFilter = .all
    var searchText = ""
    var sortOrder = [KeyPathComparator(\InstalledApp.sortName)]
    var selection = Set<InstalledApp.ID>()
    var showsInspector = true
    /// The app whose uninstall sheet is open.
    var uninstallTarget: InstalledApp?

    var windfallDays: Int {
        didSet { defaults.set(windfallDays, forKey: Self.windfallKey) }
    }

    static let windfallKey = "windfallDays"
    static let windfallChoices = [30, 60, 90, 180, 365]

    let repository: AppRepository
    private let defaults: UserDefaults
    private let now: () -> Date

    init(repository: AppRepository, defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.repository = repository
        self.defaults = defaults
        self.now = now
        let stored = defaults.integer(forKey: Self.windfallKey)
        windfallDays = stored > 0 ? stored : Freshness.defaultWindfallDays
    }

    // MARK: Loading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        let loaded = await repository.loadApps()
        // Keep sizes we already know, so a refresh doesn't blank the column.
        let known = Dictionary(apps.map { ($0.id, $0.size) }, uniquingKeysWith: { first, _ in first })
        apps = loaded.map { app in
            var app = app
            app.size = known[app.id] ?? nil
            return app
        }
        markRunning()
        selection = selection.filter { id in apps.contains { $0.id == id } }
        isLoading = false
        await measureSizes()
    }

    /// Running apps count as fresh, whatever Spotlight and the file dates say.
    func markRunning(bundleIDs: Set<String> = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))) {
        for index in apps.indices {
            apps[index].isRunning = apps[index].bundleID.map(bundleIDs.contains) ?? false
        }
    }

    /// Measures bundle sizes a few at a time and fills them in as they arrive.
    private func measureSizes() async {
        isMeasuring = true
        defer { isMeasuring = false }
        let pending = apps.filter { $0.size == nil }.map { ($0.id, $0.url) }
        let repository = repository
        await withTaskGroup(of: (String, Int64).self) { group in
            var iterator = pending.makeIterator()
            func addNext() -> Bool {
                guard let (id, url) = iterator.next() else { return false }
                group.addTask { (id, await repository.size(of: url)) }
                return true
            }
            for _ in 0..<4 where addNext() {}
            for await (id, size) in group {
                if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].size = size }
                _ = addNext()
            }
        }
    }

    // MARK: Filtering

    func freshness(of app: InstalledApp) -> Freshness {
        app.freshness(now: now(), windfallDays: windfallDays)
    }

    func apps(matching filter: AppFilter) -> [InstalledApp] {
        switch filter {
        case .all: apps
        case .windfall: apps.filter { freshness(of: $0) == .windfall && !$0.isProtected }
        case .source(let source): apps.filter { $0.source == source }
        }
    }

    func count(_ filter: AppFilter) -> Int { apps(matching: filter).count }

    var visibleApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = apps(matching: filter).filter { app in
            query.isEmpty
                || app.name.localizedStandardContains(query)
                || app.bundleID?.localizedStandardContains(query) == true
        }
        return filtered.sorted(using: sortOrder)
    }

    var visibleTotalSize: Int64 { visibleApps.reduce(0) { $0 + ($1.size ?? 0) } }

    var selectedApps: [InstalledApp] { apps.filter { selection.contains($0.id) } }

    /// The inspector shows one app at a time.
    var inspectedApp: InstalledApp? { selectedApps.count == 1 ? selectedApps.first : nil }

    // MARK: Uninstall

    func requestUninstall(_ app: InstalledApp? = nil) {
        guard let app = app ?? inspectedApp, !app.isProtected else { return }
        uninstallTarget = app
    }

    func didUninstall(_ app: InstalledApp) {
        apps.removeAll { $0.id == app.id }
        selection.remove(app.id)
    }

    var otherBundleIDs: Set<String> { Set(apps.compactMap(\.bundleID)) }
}

extension InstalledApp {
    // Non-optional keys for Table sorting.
    var sortName: String { name.lowercased() }
    var sortVersion: String { version ?? "" }
    var sortSize: Int64 { size ?? -1 }
    var sortLastUsed: Date { isRunning ? .distantFuture : lastUsed ?? .distantPast }
    var sortSource: String { source.title }
}
