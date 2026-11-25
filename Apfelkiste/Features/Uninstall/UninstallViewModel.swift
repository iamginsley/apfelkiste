import Foundation
import Observation

@Observable
@MainActor
final class UninstallViewModel {
    enum Phase: Equatable {
        case searching
        case ready
        case working
        case done
        /// The app is in the Trash, but these leftovers are still in place.
        case leftBehind([URL])
        case failed(String)
    }

    let app: InstalledApp
    let mode: RemovalMode
    private(set) var leftovers: [Leftover] = []
    var selected = Set<Leftover.ID>()
    private(set) var phase: Phase = .searching

    private let repository: AppRepository
    private let otherBundleIDs: Set<String>

    init(app: InstalledApp, mode: RemovalMode = .uninstall, repository: AppRepository, otherBundleIDs: Set<String>) {
        self.app = app
        self.mode = mode
        self.repository = repository
        self.otherBundleIDs = otherBundleIDs.subtracting([app.bundleID].compactMap(\.self))
    }

    /// Apfelkiste can't throw itself away while it is running.
    var isSelf: Bool { app.bundleID != nil && app.bundleID == Bundle.main.bundleIdentifier }

    func search() async {
        let found = await repository.leftovers(for: app, otherBundleIDs: otherBundleIDs)
        leftovers = mode == .reset ? found.filter(Self.isAppData) : found
        selected = Set(leftovers.filter(\.isPreselected).map(\.id))
        phase = .ready
    }

    /// A reset clears what the app stores, not what makes it run: its services, helpers and installer
    /// files stay, or the app would be broken.
    static func isAppData(_ leftover: Leftover) -> Bool {
        switch leftover.kind {
        case .launchAgents, .launchDaemons, .privilegedHelper, .receipt, .installedFile, .applicationScripts: false
        default: true
        }
    }

    var selectedLeftovers: [Leftover] { leftovers.filter { selected.contains($0.id) } }

    var totalSize: Int64 {
        (mode == .uninstall ? app.size ?? 0 : 0) + selectedLeftovers.reduce(0) { $0 + ($1.size ?? 0) }
    }

    /// macOS asks for the admin password when any chosen leftover (or the app) belongs to root.
    var needsAdmin: Bool { (mode == .uninstall && appNeedsAdmin) || selectedLeftovers.contains { $0.requiresAdmin || $0.isReceipt } }
    /// App Store apps belong to root.
    private var appNeedsAdmin: Bool {
        FileManager.default.fileExists(atPath: app.url.path(percentEncoded: false)) && !LeftoverFinder.isRemovableByUser(app.url)
    }

    var canConfirm: Bool {
        let ready = switch phase {
        case .ready, .failed: true
        default: false
        }
        return ready && !isSelf && !app.isProtected && (mode == .uninstall || !selected.isEmpty)
    }

    func toggle(_ leftover: Leftover) {
        if selected.contains(leftover.id) { selected.remove(leftover.id) } else { selected.insert(leftover.id) }
    }

    /// Returns true when it worked: the app is in the Trash, or (reset) its data is.
    func confirm() async -> Bool {
        guard canConfirm else { return false }
        phase = .working
        do {
            let remaining = switch mode {
            case .uninstall: try await repository.uninstall(app, leftovers: selectedLeftovers)
            case .reset: try await repository.reset(app, leftovers: selectedLeftovers)
            }
            phase = remaining.isEmpty ? .done : .leftBehind(remaining)
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    var isFinished: Bool {
        switch phase {
        case .done, .leftBehind: true
        default: false
        }
    }

    var brewCommand: String? { app.caskToken.map { "brew uninstall --cask --zap \($0)" } }
}
