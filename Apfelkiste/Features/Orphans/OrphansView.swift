import AppKit
import SwiftUI

/// Top of the "Reste" section: title on the scene, stat chips and a select-all pill.
struct OrphanHero: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        let scene = AppFilter.orphans.scene
        let groups = model.orphanGroups
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(scene.tagline)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                HStack(spacing: 10) {
                    StatChip(value: model.isScanningOrphans && groups.isEmpty ? "…" : "\(groups.count)",
                             label: groups.count == 1 ? "gelöschte App" : "gelöschte Apps")
                    StatChip(value: model.orphansTotalSize.fileSize, label: "belegt")
                    StatChip(value: "\(model.orphanSelection.count)", label: "ausgewählt")
                }
                if !groups.isEmpty {
                    let sure = Set(groups.filter { !$0.vendorStillInstalled }.map(\.id))
                    let allChosen = !model.orphanSelection.isEmpty && sure.isSubset(of: model.orphanSelection)
                    Button {
                        model.orphanSelection = allChosen ? [] : sure
                    } label: {
                        if allChosen {
                            Label("Auswahl aufheben", systemImage: "circle")
                        } else {
                            Label("Alle auswählen", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(PillButtonStyle(text: scene.top))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "sparkles")
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
                .frame(width: 168, height: 168)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

/// Leftovers grouped by the removed app's bundle ID; expand a group to see each folder.
struct OrphanList: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        List {
            if !model.orphansLeftBehind.isEmpty {
                leftBehindHint
            }
            ForEach(model.visibleOrphans) { group in
                OrphanRow(group: group)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay { emptyState }
    }

    private var leftBehindHint: some View {
        let urls = model.orphansLeftBehind
        return VStack(alignment: .leading, spacing: 8) {
            Label(urls.count == 1 ? "1 Ordner ist geblieben" : "\(urls.count) Ordner sind geblieben",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("macOS schützt die Daten anderer Apps. Mit Festplattenvollzugriff kann Apfelkiste sie entfernen, sonst zieh sie im Finder selbst in den Papierkorb.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                Button("Festplattenvollzugriff …") { FullDiskAccess.openSettings() }
                Spacer()
                Button("Ausblenden") { model.dismissLeftBehind() }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.visibleOrphans.isEmpty {
            if model.isScanningOrphans {
                ProgressView("Reste werden gesucht …")
            } else if !model.searchText.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else {
                ContentUnavailableView {
                    Label { Text("Keine Reste") } icon: { FreshnessApple(freshness: .fresh, size: 44) }
                } description: {
                    Text(model.hasFullDiskAccess
                         ? "Gelöschte Apps haben nichts zurückgelassen."
                         : "Nichts gefunden. Ohne Festplattenvollzugriff sieht Apfelkiste aber nicht alles.")
                }
            }
        }
    }
}

struct OrphanRow: View {
    let group: OrphanGroup
    @Environment(AppsViewModel.self) private var model
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(group.leftovers) { leftover in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: leftover.url.path(percentEncoded: false)))
                        .resizable()
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(leftover.kind.title)
                        Text((leftover.url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if leftover.requiresAdmin {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                            .help("Braucht dein Admin-Passwort")
                    }
                    Text(leftover.size?.fileSize ?? "…").font(.size).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([leftover.url]) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { model.orphanSelection.contains(group.id) },
                                     set: { _ in model.toggleOrphan(group) })) {
                    Text(group.displayName)
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.leftovers.first?.url.path(percentEncoded: false) ?? "/"))
                    .resizable()
                    .frame(width: Theme.listIconSize, height: Theme.listIconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .fontWeight(.medium)
                    Text("\(group.bundleID) · \(group.kindsSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if group.vendorStillInstalled {
                        Label("Vom selben Hersteller ist noch eine App da, bitte prüfen", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if group.requiresAdmin {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .help("Braucht dein Admin-Passwort")
                        .accessibilityLabel("Braucht dein Admin-Passwort")
                }
                Text(group.size.fileSize)
                    .font(.size)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleOrphan(group) }
        }
        .contextMenu {
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting(group.leftovers.map(\.url)) }
        }
    }
}

/// Floating control for the chosen leftovers, the counterpart of the uninstall bar.
struct OrphanBar: View {
    @Environment(AppsViewModel.self) private var model
    @State private var confirming = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        let count = model.orphanSelection.count
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(count == 1 ? "Reste einer App" : "Reste von \(count) Apps")
                    .font(.headline)
                Text("\(model.selectedOrphansSize.fileSize) werden frei")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)

            RoundRemoveButton(working: working) { confirming = true }
                .help("Die ausgewählten Reste in den Papierkorb legen")
                .accessibilityLabel("Ausgewählte Reste entfernen")
        }
        .confirmationDialog(count == 1 ? "Reste einer App in den Papierkorb legen?" : "Reste von \(count) Apps in den Papierkorb legen?",
                            isPresented: $confirming) {
            Button("In den Papierkorb legen", role: .destructive) { remove() }
        } message: {
            Text(model.selectedOrphans.contains(where: \.requiresAdmin)
                 ? "\(model.selectedOrphansSize.fileSize). Einige liegen außerhalb deines Benutzerordners, dafür fragt macOS nach deinem Passwort."
                 : "\(model.selectedOrphansSize.fileSize). Aus dem Papierkorb kannst du alles zurückholen.")
        }
        .alert("Reste nicht entfernt", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func remove() {
        working = true
        Task {
            do {
                try await model.removeSelectedOrphans()
            } catch {
                failure = error.localizedDescription
            }
            working = false
        }
    }
}

/// Explains Full Disk Access once, above the list, until it is granted or dismissed.
struct AccessHint: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white, .white.opacity(0.3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Festplattenvollzugriff fehlt")
                    .font(.headline)
                Text("Ohne ihn sieht Apfelkiste nicht alle Reste und kann die Container anderer Apps nicht entfernen. Schalte Apfelkiste in den Systemeinstellungen ein, dann geht es hier von selbst weiter.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Einschalten …") { FullDiskAccess.openSettings() }
                .buttonStyle(PillButtonStyle(text: model.filter.scene.top))
            Button {
                model.accessHintDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .help("Ausblenden")
            .accessibilityLabel("Hinweis ausblenden")
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }
}
