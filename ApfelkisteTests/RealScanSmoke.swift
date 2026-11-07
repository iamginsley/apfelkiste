import Foundation
import Testing
@testable import Apfelkiste

/// Scans this Mac for real and prints a summary. Opt-in: `REAL_SCAN=1 xcodebuild test … -only-testing:ApfelkisteTests/RealScanSmoke`.
struct RealScanSmoke {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REAL_SCAN"] != nil))
    func scan() async {
        let repository = LocalAppRepository()
        let apps = await repository.loadApps()
        #expect(!apps.isEmpty)
        let bySource = Dictionary(grouping: apps, by: \.source).mapValues(\.count)
        print("SCAN: \(apps.count) apps, \(bySource), protected: \(apps.filter(\.isProtected).map(\.name))")
        print("SCAN: never used: \(apps.filter { $0.lastUsed == nil }.count)")
        let ids = Set(apps.compactMap(\.bundleID))
        let interesting = ProcessInfo.processInfo.environment["REAL_SCAN_APPS"]?.split(separator: ",").map(String.init)
        let picked = interesting.map { names in apps.filter { names.contains($0.name) } } ?? Array(apps.filter { !$0.isAppleApp }.prefix(6))
        for app in picked {
            let leftovers = await repository.leftovers(for: app, otherBundleIDs: ids)
            let size = await repository.size(of: app.url)
            print("SCAN: \(app.name) \(app.version ?? "-") \(size.fileSize) team=\(app.teamID ?? "-") ")
            for leftover in leftovers {
                print("SCAN:   \(leftover.isPreselected ? "[x]" : "[ ]") \(leftover.requiresAdmin ? "🔒" : "  ") \(leftover.kind.title): \(leftover.url.path(percentEncoded: false))\(leftover.launchdLabel.map { " label=\($0)" } ?? "")")
            }
        }
    }
}
