import SwiftUI

/// The main window: sidebar with categories, the app table and an inspector for the selected app.
struct AppsView: View {
    @Environment(AppsViewModel.self) private var model
    @State private var showsInspector = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            AppSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            AppTable()
                .overlay { emptyState }
                .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
                .inspector(isPresented: $showsInspector) {
                    AppInspector()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Apps durchsuchen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Neu laden", systemImage: "arrow.clockwise")
                }
                .help("Apps neu einlesen (⌘R)")
                .disabled(model.isLoading)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    model.requestUninstall()
                } label: {
                    Label("Deinstallieren", systemImage: "trash")
                }
                .help("Ausgewählte App mit allen Resten in den Papierkorb legen (⌘⌫)")
                .disabled(model.inspectedApp.map { $0.isProtected } ?? true)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Informationen", systemImage: "sidebar.trailing")
                }
                .help("Informationen ein- oder ausblenden")
            }
        }
        .sheet(item: $model.uninstallTarget) { app in
            UninstallSheet(model: UninstallViewModel(app: app, repository: model.repository,
                                                     otherBundleIDs: model.otherBundleIDs))
        }
        .task {
            await model.load()
            applyLaunchFlags()
        }
    }

    private var title: String {
        switch model.filter {
        case .all: String(localized: "Alle Apps")
        case .windfall: Freshness.windfall.title
        case .source(let source): source.title
        }
    }

    private var subtitle: String {
        let count = model.visibleApps.count
        return count == 1 ? String(localized: "1 App") : String(localized: "\(count) Apps")
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isLoading && model.apps.isEmpty {
            ProgressView("Apfelkiste wird gefüllt …")
        } else if model.visibleApps.isEmpty && !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if model.visibleApps.isEmpty && model.filter == .windfall {
            ContentUnavailableView {
                Label { Text("Kein Fallobst") } icon: { FreshnessApple(freshness: .fresh, size: 44) }
            } description: {
                Text("Alles frisch gepflückt. Jede App wurde in den letzten \(model.windfallDays) Tagen benutzt.")
            }
        } else if model.visibleApps.isEmpty && !model.isLoading {
            ContentUnavailableView("Keine Apps", systemImage: "shippingbox",
                                   description: Text("In dieser Kategorie liegt nichts."))
        }
    }

    private func applyLaunchFlags() {
        if let filter = LaunchFlags.filter { model.filter = filter }
        if let name = LaunchFlags.select, let app = model.apps.first(where: { $0.name == name }) {
            model.selection = [app.id]
            if LaunchFlags.uninstall { model.requestUninstall(app) }
        }
    }
}

/// Count and total size of what is listed, like Finder's status bar.
private struct StatusBar: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.isMeasuring {
                ProgressView().controlSize(.small)
                Text("Größen werden ermittelt …")
            } else {
                Text("\(model.visibleApps.count) Apps · \(model.visibleTotalSize.fileSize) belegt")
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    AppsView()
        .environment(AppsViewModel(repository: DemoAppRepository()))
        .frame(width: 1100, height: 650)
}
#endif
