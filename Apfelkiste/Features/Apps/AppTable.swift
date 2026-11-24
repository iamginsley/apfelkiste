import AppKit
import SwiftUI

/// The app list, sortable by every column like "Programs and Features".
struct AppTable: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let maxSize = max(model.visibleApps.compactMap(\.size).max() ?? 1, 1)
        ScrollViewReader { proxy in
            Table(model.visibleApps, selection: $model.selection, sortOrder: $model.sortOrder) {
                TableColumn("Name", value: \.sortName) { app in
                    HStack(spacing: 8) {
                        AppIconView(url: app.url)
                        Text(app.name)
                            .fontWeight(.medium)
                        if app.isProtected {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .imageScale(.small)
                                .help("Gehört zu macOS und kann nicht entfernt werden")
                                .accessibilityLabel("Geschützt")
                        }
                    }
                }
                .width(min: 160, ideal: 220)

                TableColumn("Version", value: \.sortVersion) { app in
                    Text(app.version ?? "–")
                        .foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 64)

                TableColumn("Größe", value: \.sortSize) { app in
                    HStack(spacing: 8) {
                        if let size = app.size {
                            SizeBar(fraction: Double(size) / Double(maxSize))
                            Spacer(minLength: 0)
                            Text(size.fileSize)
                        } else {
                            Spacer(minLength: 0)
                            Text("…").foregroundStyle(.tertiary).accessibilityLabel("Wird ermittelt")
                        }
                    }
                    .font(.size)
                }
                .width(min: 110, ideal: 130)

                TableColumn("Herkunft", value: \.sortSource) { app in
                    Text(app.source.title)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 104)

                TableColumn("Zuletzt aktiv", value: \.sortLastUsed) { app in
                    HStack(spacing: 6) {
                        FreshnessApple(freshness: model.freshness(of: app))
                        Text(lastUsedText(app))
                    }
                    .accessibilityElement(children: .combine)
                }
                .width(min: 120, ideal: 150)
            }
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            // Keep the last rows clear of the floating uninstall bar.
            .contentMargins(.bottom, model.inspectedApp != nil ? 110 : 8, for: .scrollContent)
            .contextMenu(forSelectionType: InstalledApp.ID.self) { ids in
                let apps = model.apps.filter { ids.contains($0.id) }
                if let app = apps.first, apps.count == 1 {
                    Button("Öffnen") { NSWorkspace.shared.open(app.url) }
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                    Divider()
                    Button("Deinstallieren …", role: .destructive) { model.requestUninstall(app) }
                        .disabled(app.isProtected)
                }
            } primaryAction: { ids in
                guard ids.count == 1, let app = model.apps.first(where: { ids.contains($0.id) }) else { return }
                NSWorkspace.shared.open(app.url)
            }
            // Type to select, like Finder: letters typed while the list has focus jump to the matching app.
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
                      press.characters.count == 1, let character = press.characters.first,
                      character.isLetter || character.isNumber || character == " " || character.isPunctuation,
                      let id = model.typeSelect(character) else { return .ignored }
                proxy.scrollTo(id)
                return .handled
            }
        }
    }
}
