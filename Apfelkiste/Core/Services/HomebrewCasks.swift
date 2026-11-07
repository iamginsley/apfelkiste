import Foundation

/// Finds apps installed as Homebrew casks without running `brew` (which is slow and may not be on PATH).
enum HomebrewCasks {
    static let caskrooms = [URL(filePath: "/opt/homebrew/Caskroom"), URL(filePath: "/usr/local/Caskroom")]

    /// App file name ("Visual Studio Code.app") → cask token ("visual-studio-code").
    static func installedApps(caskrooms: [URL] = caskrooms, fileManager: FileManager = .default) -> [String: String] {
        var result: [String: String] = [:]
        for room in caskrooms {
            guard let tokens = try? fileManager.contentsOfDirectory(atPath: room.path(percentEncoded: false)) else { continue }
            for token in tokens where !token.hasPrefix(".") {
                // Each install keeps the cask definition in <token>/.metadata/<version>/<timestamp>/Casks/<token>.{json,rb}.
                let metadata = room.appending(path: token).appending(path: ".metadata")
                guard let files = fileManager.enumerator(at: metadata, includingPropertiesForKeys: nil) else { continue }
                for case let file as URL in files where file.deletingLastPathComponent().lastPathComponent == "Casks" {
                    guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    for app in appNames(inCaskDefinition: text) where result[app] == nil {
                        result[app] = token
                    }
                }
            }
        }
        return result
    }

    /// The `.app` names a cask definition installs, from either the JSON or the Ruby form.
    static func appNames(inCaskDefinition text: String) -> Set<String> {
        let pattern = /["']([^"'\/\\]+\.app)["']/
        return Set(text.matches(of: pattern).map { String($0.output.1) })
    }
}
