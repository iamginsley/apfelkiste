import AppKit
import SwiftUI

/// Shows what will go to the Trash (the app plus its leftovers) and lets the user untick anything.
struct UninstallSheet: View {
    @State var model: UninstallViewModel
    @Environment(AppsViewModel.self) private var apps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            content
                .frame(minHeight: 220)
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 560)
        .task { await model.search() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView(url: model.app.url, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("„\(model.app.name)“ deinstallieren?")
                    .font(.title3.weight(.semibold))
                Text("Die App und die ausgewählten Reste kommen in den Papierkorb. Von dort kannst du alles zurückholen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if model.isSelf {
            ContentUnavailableView {
                Label("Die Kiste kann sich nicht selbst wegwerfen", systemImage: "shippingbox")
            } description: {
                Text("Beende Apfelkiste und zieh sie im Finder in den Papierkorb.")
            }
        } else {
            switch model.phase {
            case .searching:
                ProgressView("Reste werden gesucht …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                ContentUnavailableView {
                    Label { Text("Im Papierkorb") } icon: { FreshnessApple(freshness: .windfall, size: 44) }
                } description: {
                    Text("\(model.app.name) ist raus aus der Kiste.")
                }
            default:
                list
            }
        }
    }

    private var list: some View {
        List {
            Section {
                row(icon: AnyView(AppIconView(url: model.app.url)), title: model.app.name,
                    detail: model.app.url.deletingLastPathComponent().path(percentEncoded: false), size: model.app.size)
            } header: {
                Text("App")
            }

            Section {
                if model.leftovers.isEmpty {
                    Text("Keine Reste gefunden. Sauber!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.leftovers) { leftover in
                        Toggle(isOn: Binding(get: { model.selected.contains(leftover.id) },
                                             set: { _ in model.toggle(leftover) })) {
                            row(icon: AnyView(Image(nsImage: NSWorkspace.shared.icon(forFile: leftover.url.path(percentEncoded: false)))
                                    .resizable().frame(width: Theme.listIconSize, height: Theme.listIconSize)),
                                title: leftover.kind.title,
                                detail: leftover.url.abbreviatedPath,
                                size: leftover.size,
                                note: leftover.match == .likely ? String(localized: "Wahrscheinlich, bitte prüfen") : nil)
                        }
                        .contextMenu {
                            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([leftover.url]) }
                        }
                    }
                }
            } header: {
                Text("Reste in deiner Library")
            }

            if let command = model.brewCommand {
                Section("Homebrew") {
                    Text("Installiert per Homebrew. Damit Homebrew Bescheid weiß, kannst du stattdessen im Terminal ausführen:")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(command).font(.callout.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("Kopieren", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        .labelStyle(.iconOnly)
                        .help("Befehl kopieren")
                    }
                }
            }
        }
        .listStyle(.inset)
        .disabled(model.phase == .working)
    }

    private func row(icon: AnyView, title: String, detail: String, size: Int64?, note: String? = nil) -> some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let note {
                    Label(note, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(size?.fileSize ?? "…").font(.size).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            if case .failed(let message) = model.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if model.phase == .ready, !model.isSelf {
                Text("Frei werden \(model.totalSize.fileSize)")
                    .font(.size)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.phase == .done || model.isSelf {
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    Task {
                        if await model.confirm() {
                            withAnimation(reduceMotion ? nil : .default) { apps.didUninstall(model.app) }
                        }
                    }
                } label: {
                    if model.phase == .working {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("In den Papierkorb legen")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canConfirm)
            }
        }
    }
}

private extension URL {
    /// "~/Library/Caches/…" instead of the full home path.
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
