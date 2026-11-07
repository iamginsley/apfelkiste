import CoreServices
import Foundation

/// When an app was last active. Spotlight's "last opened" date is missing for many apps (anything started
/// at login, from Setapp, by a helper, or never indexed), so it is combined with the dates the app's own
/// files in ~/Library last changed: an app that runs writes its preferences, caches or web data.
enum UsageEvidence {
    /// Files and folders an app touches while it runs. Only the entries themselves are read (their
    /// modification date), never their contents, so protected containers don't trigger a privacy prompt.
    static func traces(bundleID: String, library: URL) -> [URL] {
        [
            "Preferences/\(bundleID).plist",
            "Application Support/\(bundleID)",
            "Caches/\(bundleID)",
            "HTTPStorages/\(bundleID)",
            "Saved Application State/\(bundleID).savedState",
            "Containers/\(bundleID)",
        ].map { library.appending(path: $0) }
    }

    static func lastActivity(appURL: URL, bundleID: String?, library: URL = .homeDirectory.appending(path: "Library"),
                             fileManager: FileManager = .default) -> Date? {
        var dates = spotlightDates(of: appURL)
        if let bundleID {
            dates += traces(bundleID: bundleID, library: library).compactMap { url in
                (try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
            }
        }
        return latest(dates, notAfter: .now)
    }

    /// The newest date, ignoring dates in the future (clock skew, files from another Mac).
    static func latest(_ dates: [Date], notAfter now: Date) -> Date? {
        dates.filter { $0 <= now.addingTimeInterval(60) }.max()
    }

    /// "Last opened" plus the list of days it was used, both from Spotlight.
    static func spotlightDates(of url: URL) -> [Date] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return [] }
        var dates: [Date] = []
        if let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { dates.append(last) }
        if let used = MDItemCopyAttribute(item, "kMDItemUsedDates" as CFString) as? [Date] { dates += used }
        return dates
    }
}
