import AppKit
import SwiftUI
import Testing
@testable import Apfelkiste

/// Renders the main window with demo data to PNGs, for README and design reviews.
/// `SNAPSHOT_DIR=/some/dir xcodebuild test -scheme Apfelkiste -only-testing:ApfelkisteTests/SnapshotRender`
@MainActor
struct SnapshotRender {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
    func render() async throws {
        let dir = URL(filePath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]!)
        let cases: [(String, AppFilter, String?, NSAppearance.Name)] = [
            ("alle-hell", .all, "Tonstudio", .aqua),
            ("alle-dunkel", .all, "Tonstudio", .darkAqua),
            ("fallobst", .windfall, "Vokabeltrainer", .aqua),
        ]
        for (name, filter, selected, appearance) in cases {
            let defaults = UserDefaults(suiteName: "apfelkiste-snapshot-\(UUID().uuidString)")!
            let model = AppsViewModel(repository: DemoAppRepository(), defaults: defaults)
            await model.load()
            model.filter = filter
            model.sortOrder = [KeyPathComparator(\InstalledApp.sortSize, order: .reverse)]
            if let selected, let app = model.apps.first(where: { $0.name == selected }) { model.selection = [app.id] }
            try await snapshot(AppsView().environment(model), size: CGSize(width: 1180, height: 640),
                               appearance: appearance, to: dir.appending(path: "\(name).png"))
        }

        let app = try #require(await DemoAppRepository().loadApps().first { $0.name == "Tonstudio" })
        let sheet = UninstallViewModel(app: app, repository: DemoAppRepository(), otherBundleIDs: [])
        await sheet.search()
        try await snapshot(UninstallSheet(model: sheet).environment(AppsViewModel(repository: DemoAppRepository())),
                           size: CGSize(width: 560, height: 480), appearance: .aqua, to: dir.appending(path: "deinstallieren.png"))
    }

    private func snapshot(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) async throws {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(1.5))
        let frame = try #require(window.contentView?.superview?.frame)
        let rep = try #require(window.contentView?.superview?.bitmapImageRepForCachingDisplay(in: frame))
        window.contentView?.superview?.cacheDisplay(in: frame, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
