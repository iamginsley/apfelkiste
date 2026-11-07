import Foundation

enum DirectorySize {
    /// Bytes the item occupies on disk (allocated, like Finder's "on disk"), recursing into folders and bundles.
    static func allocatedSize(of url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return fileSize(values) }

        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isDirectory != true, values.isSymbolicLink != true else { continue }
            total += fileSize(values)
        }
        return total
    }

    private static func fileSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
