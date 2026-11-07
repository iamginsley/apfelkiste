import SwiftUI

struct SettingsView: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Fallobst nach", selection: $model.windfallDays) {
                    ForEach(AppsViewModel.windfallChoices, id: \.self) { days in
                        Text("\(days) Tagen").tag(days)
                    }
                }
            } footer: {
                Text("Apps, die du so lange nicht geöffnet hast, landen unter Fallobst.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Papierkorb statt Löschen") {
                    Text("Immer").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Apfelkiste löscht nichts endgültig. Alles landet im Papierkorb und lässt sich zurückholen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
