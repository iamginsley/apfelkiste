import Charts
import SwiftUI

/// The top of every section: big title on the gradient, stat chips, and the freshness ring.
struct CrateHero: View {
    @Environment(AppsViewModel.self) private var model

    var body: some View {
        let scene = model.filter.scene
        let apps = model.visibleApps
        let counts = Dictionary(grouping: apps, by: model.freshness(of:)).mapValues(\.count)
        let windfall = counts[.windfall] ?? 0

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
                    StatChip(value: "\(apps.count)", label: apps.count == 1 ? "App" : "Apps")
                    StatChip(value: model.isMeasuring ? "…" : model.visibleTotalSize.fileSize, label: "belegt")
                    StatChip(value: "\(windfall)", label: "Fallobst")
                }
                if windfall > 0, model.filter != .windfall {
                    Button {
                        model.filter = .windfall
                    } label: {
                        Label("Fallobst aufsammeln", systemImage: "basket.fill")
                    }
                    .buttonStyle(PillButtonStyle(text: scene.top))
                    .help("Apps zeigen, die du seit \(model.windfallDays) Tagen nicht benutzt hast")
                }
            }
            Spacer(minLength: 0)
            FreshnessRing(counts: counts, center: model.visibleTotalSize.fileSize)
                .frame(width: 168, height: 168)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

/// White pill with the scene's dark color as text (over 12:1), the hero's one call to action.
struct PillButtonStyle: ButtonStyle {
    let text: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(text)
            .padding(.horizontal, 18)
            .frame(minHeight: 36)
            .background(.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
    }
}

/// A number with a small label, on a faint white plate. Content layer, so no glass.
struct StatChip: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 84, alignment: .leading)
        .background(.white.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }
}

/// Fresh, ripening and windfall as a donut. Swift Charts brings VoiceOver and Audio Graphs along.
struct FreshnessRing: View {
    let counts: [Freshness: Int]
    let center: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = counts.values.reduce(0, +)
        Chart(Freshness.allCases, id: \.self) { freshness in
            SectorMark(angle: .value("Apps", total == 0 ? (freshness == .fresh ? 1 : 0) : counts[freshness] ?? 0),
                       innerRadius: .ratio(0.7), angularInset: 2.5)
                .cornerRadius(5)
                .foregroundStyle(total == 0 ? Color.white.opacity(0.15) : freshness.color)
                .accessibilityLabel(freshness.title)
                .accessibilityValue("\(counts[freshness] ?? 0) Apps")
        }
        .chartLegend(.hidden)
        .animation(reduceMotion ? nil : .smooth, value: counts)
        .overlay {
            VStack(spacing: 2) {
                Text(center)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                HStack(spacing: 8) {
                    ForEach(Freshness.allCases, id: \.self) { freshness in
                        HStack(spacing: 3) {
                            FreshnessApple(freshness: freshness, size: 10)
                            Text("\(counts[freshness] ?? 0)").monospacedDigit()
                        }
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// A slim bar behind the size, relative to the biggest app in view, so heavy apps stand out while scanning.
struct SizeBar: View {
    let fraction: Double
    var tint: Color = .white

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(3, proxy.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(width: 44, height: 5)
            .accessibilityHidden(true)
    }
}
