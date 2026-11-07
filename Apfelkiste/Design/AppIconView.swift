import AppKit
import SwiftUI

/// The app's Finder icon, cached because the table asks for it on every scroll.
struct AppIconView: View {
    let url: URL
    var size: CGFloat = Theme.listIconSize

    var body: some View {
        Image(nsImage: IconCache.shared.icon(for: url))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSURL, NSImage>()

    func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let path = url.path(percentEncoded: false)
        let icon: NSImage
        #if DEBUG
        if !FileManager.default.fileExists(atPath: path), let demo = DemoIcons.icon(for: url) {
            icon = demo
        } else {
            icon = NSWorkspace.shared.icon(forFile: path)
        }
        #else
        icon = NSWorkspace.shared.icon(forFile: path)
        #endif
        cache.setObject(icon, forKey: url as NSURL)
        return icon
    }
}
