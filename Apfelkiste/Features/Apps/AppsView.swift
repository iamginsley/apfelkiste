import SwiftUI

/// The main window: a colored scene per section, hero on top, the app list and the details as frosted cards,
/// and a floating bar with the big round uninstall button for the selected app.
struct AppsView: View {
    @Environment(AppsViewModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            AppSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                CrateHero()
                HStack(alignment: .top, spacing: 16) {
                    AppTable()
                        .overlay { emptyState }
                        .frostedCard()
                    if model.showsInspector, model.inspectedApp != nil {
                        AppInspector()
                            .frame(width: 300)
                            .frostedCard()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .overlay(alignment: .bottom) {
                if let app = model.inspectedApp, !app.isProtected {
                    UninstallBar(app: app)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.inspectedApp?.id)
            .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.showsInspector)
        }
        .containerBackground(for: .window) { CrateBackground(scene: model.filter.scene) }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .navigationTitle(model.filter.windowTitle)
        .preferredColorScheme(.dark)
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
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showsInspector.toggle()
                } label: {
                    Label("Informationen", systemImage: "info.circle")
                }
                .help("Informationen ein- oder ausblenden (⌥⌘I)")
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
                Text("Alles frisch gepflückt. Jede App war in den letzten \(model.windfallDays) Tagen aktiv.")
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

extension AppFilter {
    /// Window title for the Window menu and Mission Control; the hero shows the visible title.
    var windowTitle: String {
        switch self {
        case .all: String(localized: "Alle Apps")
        case .windfall: Freshness.windfall.title
        case .source(let source): source.title
        }
    }
}

extension View {
    /// Content cards on the scene: a standard material (not Liquid Glass, which belongs to controls) with a
    /// hairline so the edge stays visible on every gradient.
    func frostedCard() -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

/// Floating control for the selected app: what it frees, and the big round button. This floats above the
/// content, so it is the one place that gets Liquid Glass.
struct UninstallBar: View {
    let app: InstalledApp
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                AppIconView(url: app.url, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.size.map { "\($0.fileSize) plus Reste" } ?? String(localized: "Größe wird ermittelt …"))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 22)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Button {
                model.requestUninstall(app)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Entfernen")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xC62F3A), Color(hex: 0x9E1F2B)],
                                                 startPoint: .top, endPoint: .bottom))
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .contentShape(Circle())
            }
            .buttonStyle(RoundButtonStyle())
            .help("\(app.name) mit allen Resten in den Papierkorb legen (⌘⌫)")
            .accessibilityLabel("\(app.name) deinstallieren")
        }
    }
}

/// Presses in a little; grows a touch on hover.
struct RoundButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.05 : 1)
            .shadow(color: .black.opacity(0.35), radius: hovering ? 16 : 10, y: 6)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: hovering)
            .animation(reduceMotion ? nil : .spring(duration: 0.2), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

#if DEBUG
#Preview {
    AppsView()
        .environment(AppsViewModel(repository: DemoAppRepository()))
        .frame(width: 1180, height: 760)
}
#endif
