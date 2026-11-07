import SwiftUI

struct AppSidebar: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.filter) {
            Section("Kiste") {
                row(.all, "Alle Apps") { Image(systemName: "shippingbox") }
                row(.windfall, Freshness.windfall.title) { FreshnessApple(freshness: .windfall, size: 15) }
                    .help("Apps, die du seit \(model.windfallDays) Tagen nicht geöffnet hast")
            }
            Section("Herkunft") {
                ForEach([AppSource.appStore, .homebrew, .direct, .apple], id: \.self) { source in
                    row(.source(source), source.title) { Image(systemName: source.symbol) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ filter: AppFilter, _ title: String, @ViewBuilder icon: () -> some View) -> some View {
        Label { Text(title) } icon: { icon() }
            .badge(model.count(filter))
            .tag(filter)
    }
}
