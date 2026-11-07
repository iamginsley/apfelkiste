#if DEBUG
import AppKit
import Foundation

/// Sample apps for screenshots and tests (`-ApfelkisteDemo`). Nothing touches the disk.
struct DemoAppRepository: AppRepository {
    struct Sample {
        let name: String
        let symbol: String
        let hue: Double
        let source: AppSource
        let daysAgo: Int?
        let megabytes: Int
        let version: String
    }

    static let samples: [Sample] = [
        Sample(name: "Pixelmeister", symbol: "paintbrush.pointed.fill", hue: 0.78, source: .appStore, daysAgo: 0, megabytes: 1_840, version: "4.2"),
        Sample(name: "Kaffeeklatsch", symbol: "cup.and.saucer.fill", hue: 0.08, source: .direct, daysAgo: 1, megabytes: 312, version: "2.0.1"),
        Sample(name: "Wetterfrosch", symbol: "cloud.sun.fill", hue: 0.58, source: .appStore, daysAgo: 3, megabytes: 96, version: "7.1"),
        Sample(name: "Notizblock", symbol: "note.text", hue: 0.14, source: .homebrew, daysAgo: 12, megabytes: 214, version: "1.9.3"),
        Sample(name: "Dackelplaner", symbol: "pawprint.fill", hue: 0.06, source: .direct, daysAgo: 45, megabytes: 58, version: "0.9"),
        Sample(name: "Tonstudio", symbol: "waveform", hue: 0.95, source: .direct, daysAgo: 70, megabytes: 4_620, version: "11.0"),
        Sample(name: "Kartenhaus", symbol: "map.fill", hue: 0.36, source: .homebrew, daysAgo: 160, megabytes: 402, version: "3.4.0"),
        Sample(name: "Zeiterfassung", symbol: "stopwatch.fill", hue: 0.5, source: .appStore, daysAgo: 400, megabytes: 74, version: "5.5"),
        Sample(name: "Vokabeltrainer", symbol: "character.book.closed.fill", hue: 0.66, source: .direct, daysAgo: nil, megabytes: 1_120, version: "2.3"),
        Sample(name: "Keynote", symbol: "chart.bar.doc.horizontal.fill", hue: 0.6, source: .apple, daysAgo: 21, megabytes: 760, version: "14.4"),
    ]

    static func url(for name: String) -> URL { URL(filePath: "/Applications/\(name).app") }

    func loadApps() async -> [InstalledApp] {
        let now = Date.now
        return Self.samples.map { sample in
            InstalledApp(
                url: Self.url(for: sample.name),
                name: sample.name,
                bundleID: sample.source == .apple ? "com.apple.\(sample.name)" : "de.beispiel.\(sample.name.lowercased())",
                version: sample.version,
                source: sample.source,
                caskToken: sample.source == .homebrew ? sample.name.lowercased() : nil,
                isProtected: false,
                teamID: "DEMO123456",
                installDate: Calendar.current.date(byAdding: .day, value: -((sample.daysAgo ?? 300) + 30), to: now),
                lastUsed: sample.daysAgo.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) },
                size: nil
            )
        }
    }

    func size(of url: URL) async -> Int64 {
        try? await Task.sleep(for: .milliseconds(Int.random(in: 50...300)))
        let name = url.deletingPathExtension().lastPathComponent
        let megabytes = Self.samples.first { $0.name == name }?.megabytes ?? 10
        return Int64(megabytes) * 1_000_000
    }

    func leftovers(for app: InstalledApp, otherBundleIDs: Set<String>) async -> [Leftover] {
        try? await Task.sleep(for: .milliseconds(400))
        let library = URL(filePath: "/Users/demo/Library")
        let id = app.bundleID ?? app.name
        return [
            Leftover(url: library.appending(path: "Application Support/\(id)"), kind: .applicationSupport, match: .bundleID, size: 182_000_000),
            Leftover(url: library.appending(path: "Caches/\(id)"), kind: .caches, match: .bundleID, size: 96_400_000),
            Leftover(url: library.appending(path: "Preferences/\(id).plist"), kind: .preferences, match: .bundleID, size: 4_096),
            Leftover(url: library.appending(path: "Saved Application State/\(id).savedState"), kind: .savedState, match: .bundleID, size: 28_000),
            Leftover(url: library.appending(path: "Logs/\(app.name)"), kind: .logs, match: .likely, size: 1_300_000),
        ]
    }

    @MainActor
    func uninstall(_ app: InstalledApp, leftovers: [Leftover]) async throws {
        try await Task.sleep(for: .milliseconds(700))
    }
}

/// Colorful placeholder icons for the demo apps.
@MainActor
enum DemoIcons {
    static func icon(for url: URL) -> NSImage? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let sample = DemoAppRepository.samples.first(where: { $0.name == name }) else { return nil }
        let size = NSSize(width: 256, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            let tile = rect.insetBy(dx: 20, dy: 20)
            let path = NSBezierPath(roundedRect: tile, xRadius: 50, yRadius: 50)
            let top = NSColor(hue: sample.hue, saturation: 0.55, brightness: 0.98, alpha: 1)
            let bottom = NSColor(hue: sample.hue, saturation: 0.8, brightness: 0.78, alpha: 1)
            NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 110, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: sample.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let symbolSize = symbol.size
                symbol.draw(in: NSRect(x: tile.midX - symbolSize.width / 2, y: tile.midY - symbolSize.height / 2,
                                       width: symbolSize.width, height: symbolSize.height))
            }
            return true
        }
    }
}
#endif
