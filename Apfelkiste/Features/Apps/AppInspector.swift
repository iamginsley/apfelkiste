import AppKit
import SwiftUI

/// Details of the selected app, laid out like Finder's Get Info: plain content on the window
/// background, no cards. Glass belongs to the toolbar and sidebar, not here.
struct AppInspector: View {
    @Environment(AppsViewModel.self) private var model
    /// Leftovers of the shown app, loaded in the background: what uninstalling would really free.
    @State private var leftovers: (appID: String, count: Int, size: Int64)?

    var body: some View {
        if let app = model.inspectedApp {
            ScrollView {
                details(app)
                    .padding(20)
            }
            .task(id: app.id) {
                let found = await model.repository.leftovers(for: app, otherBundleIDs: model.otherBundleIDs)
                leftovers = (app.id, found.count, found.reduce(0) { $0 + ($1.size ?? 0) })
            }
        } else {
            ContentUnavailableView {
                Label("Keine Auswahl", systemImage: "shippingbox")
            } description: {
                Text(model.selection.count > 1 ? "Wähl eine einzelne App für Details." : "Wähl eine App aus der Liste.")
            }
        }
    }

    private func details(_ app: InstalledApp) -> some View {
        let freshness = model.freshness(of: app)
        return VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 6) {
                AppIconView(url: app.url, size: Theme.inspectorIconSize)
                    .padding(.bottom, 4)
                Text(app.name)
                    .font(.crateTitle)
                    .multilineTextAlignment(.center)
                Text(app.size?.fileSize ?? String(localized: "Größe wird ermittelt …"))
                    .font(.heroSize)
                    .foregroundStyle(.secondary)
                Label {
                    Text(freshness.title)
                } icon: {
                    FreshnessApple(freshness: freshness, size: 14)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                row("Version", app.version ?? "–")
                row("Herkunft", app.source.title)
                row("Zuletzt aktiv", lastUsedText(app))
                if let date = app.installDate {
                    row("Hinzugefügt", date.formatted(date: .abbreviated, time: .omitted))
                }
                if let id = app.bundleID {
                    row("Bundle-ID", id)
                }
                row("Ort", (app.url.deletingLastPathComponent().path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
            }
            .font(.callout)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Was wirklich drinsteckt")
                    .font(.headline)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    let current = leftovers?.appID == app.id ? leftovers : nil
                    sizeRow("App", app.size)
                    sizeRow(current.map { $0.count == 1 ? "1 Rest" : "\($0.count) Reste" } ?? String(localized: "Reste"),
                            current?.size, searching: current == nil)
                    Divider().gridCellUnsizedAxes(.horizontal)
                    sizeRow("Frei nach dem Deinstallieren", current.map { (app.size ?? 0) + $0.size }, emphasized: true)
                }
                .font(.callout)
            }

            Divider()

            if app.isProtected {
                Label("Gehört zu macOS und kann nicht entfernt werden.", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Deinstallieren …", systemImage: "trash", role: .destructive) {
                        model.requestUninstall(app)
                    }
                    Button("Im Finder zeigen", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([app.url])
                    }
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
        }
    }

    private func sizeRow(_ label: String, _ size: Int64?, searching: Bool = false, emphasized: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Text(size.map(\.fileSize) ?? (searching ? String(localized: "wird gesucht …") : "…"))
                .monospacedDigit()
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(size == nil ? .tertiary : .primary)
                .gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
