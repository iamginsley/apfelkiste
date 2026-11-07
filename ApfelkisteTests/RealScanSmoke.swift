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
        for app in apps.filter({ !$0.isAppleApp }).prefix(6) {
            let leftovers = await repository.leftovers(for: app, otherBundleIDs: ids)
            let size = await repository.size(of: app.url)
            print("SCAN: \(app.name) \(app.version ?? "-") \(size.fileSize) team=\(app.teamID ?? "-") leftovers=\(leftovers.map { "\($0.kind.title):\($0.url.lastPathComponent)" })")
        }
    }
}
