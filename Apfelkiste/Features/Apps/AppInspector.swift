import AppKit
import SwiftUI

/// Details of the selected app, laid out like Finder's Get Info: plain content on the window
/// background, no cards. Glass belongs to the toolbar and sidebar, not here.
struct AppInspector: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        if let app = model.inspectedApp {
            ScrollView {
                details(app)
                    .padding(20)
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
                row("Zuletzt benutzt", lastUsedText(app.lastUsed))
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
