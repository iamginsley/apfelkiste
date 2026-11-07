import SwiftUI

@main
struct ApfelkisteApp: App {
    @State private var model = AppsViewModel(repository: Self.makeRepository())

    var body: some Scene {
        Window("Apfelkiste", id: "main") {
            AppsView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Neu laden") { Task { await model.load() } }
                    .keyboardShortcut("r")
                Button(model.showsInspector ? "Informationen ausblenden" : "Informationen einblenden") {
                    model.showsInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
            CommandGroup(after: .pasteboard) {
                Button("Deinstallieren …") { model.requestUninstall() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.inspectedApp.map { $0.isProtected } ?? true)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    private static func makeRepository() -> AppRepository {
        #if DEBUG
        if LaunchFlags.demo { return DemoAppRepository() }
        #endif
        return LocalAppRepository()
    }
}

/// Launch arguments for screenshots and UI tests. Only honored in Debug builds.
enum LaunchFlags {
    #if DEBUG
    static let demo = ProcessInfo.processInfo.arguments.contains("-ApfelkisteDemo")
    /// `-ApfelkisteFilter windfall|appStore|homebrew|direct|apple` opens that sidebar entry.
    static let filter: AppFilter? = {
        guard let raw = UserDefaults.standard.string(forKey: "ApfelkisteFilter") else { return nil }
        if raw == "windfall" { return .windfall }
        return AppSource(rawValue: raw).map(AppFilter.source)
    }()
    /// `-ApfelkisteSelect <name>` selects that app (and opens its inspector).
    static let select = UserDefaults.standard.string(forKey: "ApfelkisteSelect")
    /// `-ApfelkisteUninstall` opens the uninstall sheet for the selected app.
    static let uninstall = ProcessInfo.processInfo.arguments.contains("-ApfelkisteUninstall")
    #else
    static let demo = false
    static let filter: AppFilter? = nil
    static let select: String? = nil
    static let uninstall = false
    #endif
}
