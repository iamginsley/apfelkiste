import SwiftUI

/// Sections as colored module tiles. The sidebar's glass picks up the section's gradient behind it.
struct AppSidebar: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.filter) {
            Section("Kiste") {
                row(.all, "Alle Apps")
                row(.windfall, Freshness.windfall.title)
                    .help("Apps, die du seit \(model.windfallDays) Tagen nicht benutzt hast")
                row(.orphans, String(localized: "Reste"))
                    .help("Was gelöschte Apps zurückgelassen haben")
            }
            Section("Herkunft") {
                ForEach([AppSource.appStore, .homebrew, .direct, .apple], id: \.self) { source in
                    row(.source(source), source.title)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ filter: AppFilter, _ title: String) -> some View {
        Label {
            Text(title)
        } icon: {
            SceneTile(scene: filter.scene, size: 22)
        }
        .badge(model.count(filter))
        .tag(filter)
        .padding(.vertical, 2)
    }
}
