import AppKit
import SwiftUI

/// Details of the selected app, like Finder's "Get Info".
struct AppInspector: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        if let app = model.inspectedApp {
            details(app)
        } else {
            ContentUnavailableView {
                Label("Keine App ausgewählt", systemImage: "shippingbox")
            } description: {
                Text(model.selection.count > 1 ? "Wähl eine einzelne App für Details." : "Wähl links eine App aus.")
            }
        }
    }

    private func details(_ app: InstalledApp) -> some View {
        let freshness = model.freshness(of: app)
        return Form {
            Section {
                VStack(spacing: 10) {
                    AppIconView(url: app.url, size: Theme.inspectorIconSize)
                    Text(app.name)
                        .font(.crateTitle)
                        .multilineTextAlignment(.center)
                    if let size = app.size {
                        Text(size.fileSize).font(.heroSize).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        FreshnessApple(freshness: freshness, size: 16)
                        Text(freshness.title)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Informationen") {
                LabeledContent("Version", value: app.version ?? "–")
                LabeledContent("Herkunft", value: app.source.title)
                LabeledContent("Zuletzt benutzt", value: lastUsedText(app.lastUsed))
                if let date = app.installDate {
                    LabeledContent("Hinzugefügt", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                if let id = app.bundleID {
                    LabeledContent("Bundle-ID") { Text(id).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                }
                LabeledContent("Ort") {
                    Text(app.url.deletingLastPathComponent().path(percentEncoded: false))
                        .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                }
            }

            Section {
                Button("Im Finder zeigen", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
                if app.isProtected {
                    Label("Gehört zu macOS und kann nicht entfernt werden.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Deinstallieren …", systemImage: "trash", role: .destructive) {
                        model.requestUninstall(app)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
