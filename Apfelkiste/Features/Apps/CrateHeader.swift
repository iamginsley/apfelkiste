import SwiftUI

/// The top of the list: how full the crate is and how fresh its apples are. Content layer, no glass.
/// The harvest bar is the app's signature moment: one look shows how much of the Mac is windfall.
struct CrateHeader: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        let apps = model.visibleApps
        let counts = Dictionary(grouping: apps, by: model.freshness(of:)).mapValues(\.count)
        let windfall = counts[.windfall] ?? 0

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(apps.count == 1 ? "1 Apfel in der Kiste" : "\(apps.count) Äpfel in der Kiste")
                        .font(.crateHeadline)
                    Text(model.isMeasuring ? String(localized: "Größen werden ermittelt …")
                                           : String(localized: "\(model.visibleTotalSize.fileSize) belegt"))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if windfall > 0, model.filter != .windfall {
                    Button {
                        model.filter = .windfall
                    } label: {
                        Label("\(windfall) × Fallobst aufsammeln", systemImage: "basket")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Apps zeigen, die du seit \(model.windfallDays) Tagen nicht benutzt hast")
                }
            }
            HarvestBar(counts: counts)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// Fresh, ripening and windfall apps as one segmented bar, with a legend that doubles as the key.
struct HarvestBar: View {
    let counts: [Freshness: Int]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Int { max(counts.values.reduce(0, +), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(Freshness.allCases, id: \.self) { freshness in
                        let count = counts[freshness] ?? 0
                        if count > 0 {
                            Capsule()
                                .fill(freshness.color.gradient)
                                .frame(width: max(6, (proxy.size.width - 6) * CGFloat(count) / CGFloat(total)))
                                .help("\(freshness.title): \(count)")
                        }
                    }
                }
            }
            .frame(height: 10)
            .animation(reduceMotion ? nil : .smooth, value: counts)

            HStack(spacing: 16) {
                ForEach(Freshness.allCases, id: \.self) { freshness in
                    HStack(spacing: 5) {
                        FreshnessApple(freshness: freshness, size: 12)
                        Text("\(freshness.title) \(counts[freshness] ?? 0)")
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Freshness.allCases.map { "\($0.title): \(counts[$0] ?? 0)" }.joined(separator: ", "))
    }
}

/// A slim bar behind the size, relative to the biggest app in view, so heavy apps stand out while scanning.
struct SizeBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: max(3, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(width: 36, height: 5)
            .accessibilityHidden(true)
    }
}
