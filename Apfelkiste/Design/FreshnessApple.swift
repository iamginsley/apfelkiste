import SwiftUI

/// The signature element: a little apple per app. Red and upright when used recently, orange while it
/// ripens, brown and fallen over when it is windfall. Shape and tilt carry the state, not color alone.
struct FreshnessApple: View {
    let freshness: Freshness
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppleBody()
                .fill(freshness.color.gradient)
            Leaf()
                .fill(Color.leaf)
            Stem()
                .stroke(Color.appleWindfall, style: StrokeStyle(lineWidth: max(1, size / 14), lineCap: .round))
        }
        .frame(width: size, height: size)
        .rotationEffect(freshness == .windfall ? .degrees(100) : .zero)
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: freshness)
        .accessibilityElement()
        .accessibilityLabel(freshness.title)
    }
}

private struct AppleBody: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.5, 0.32))
        path.addCurve(to: p(0.96, 0.56), control1: p(0.66, 0.2), control2: p(0.98, 0.26))
        path.addCurve(to: p(0.5, 1.0), control1: p(0.94, 0.86), control2: p(0.7, 1.0))
        path.addCurve(to: p(0.04, 0.56), control1: p(0.3, 1.0), control2: p(0.06, 0.86))
        path.addCurve(to: p(0.5, 0.32), control1: p(0.02, 0.26), control2: p(0.34, 0.2))
        path.closeSubpath()
        return path
    }
}

private struct Leaf: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.52, 0.24))
        path.addQuadCurve(to: p(0.86, 0.02), control: p(0.6, 0.0))
        path.addQuadCurve(to: p(0.52, 0.24), control: p(0.82, 0.24))
        path.closeSubpath()
        return path
    }
}

private struct Stem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.5 * rect.width, y: rect.minY + 0.34 * rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 0.42 * rect.width, y: rect.minY + 0.06 * rect.height),
                          control: CGPoint(x: rect.minX + 0.5 * rect.width, y: rect.minY + 0.14 * rect.height))
        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(Freshness.allCases, id: \.self) { freshness in
            VStack {
                FreshnessApple(freshness: freshness, size: 48)
                Text(freshness.title)
            }
        }
    }
    .padding()
}
