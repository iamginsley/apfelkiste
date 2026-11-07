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
        case failed(String)
    }

    let app: InstalledApp
    private(set) var leftovers: [Leftover] = []
    var selected = Set<Leftover.ID>()
    private(set) var phase: Phase = .searching

    private let repository: AppRepository
    private let otherBundleIDs: Set<String>

    init(app: InstalledApp, repository: AppRepository, otherBundleIDs: Set<String>) {
        self.app = app
        self.repository = repository
        self.otherBundleIDs = otherBundleIDs.subtracting([app.bundleID].compactMap(\.self))
    }

    /// Apfelkiste can't throw itself away while it is running.
    var isSelf: Bool { app.bundleID != nil && app.bundleID == Bundle.main.bundleIdentifier }

    func search() async {
        leftovers = await repository.leftovers(for: app, otherBundleIDs: otherBundleIDs)
        selected = Set(leftovers.filter(\.isPreselected).map(\.id))
        phase = .ready
    }

    var selectedLeftovers: [Leftover] { leftovers.filter { selected.contains($0.id) } }

    var totalSize: Int64 {
        (app.size ?? 0) + selectedLeftovers.reduce(0) { $0 + ($1.size ?? 0) }
    }

    var canConfirm: Bool {
        let ready = switch phase {
        case .ready, .failed: true
        default: false
        }
        return ready && !isSelf && !app.isProtected
    }

    func toggle(_ leftover: Leftover) {
        if selected.contains(leftover.id) { selected.remove(leftover.id) } else { selected.insert(leftover.id) }
    }

    /// Returns true when the app is in the Trash.
    func confirm() async -> Bool {
        guard canConfirm else { return false }
        phase = .working
        do {
            try await repository.uninstall(app, leftovers: selectedLeftovers)
            phase = .done
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    var brewCommand: String? { app.caskToken.map { "brew uninstall --cask --zap \($0)" } }
}
