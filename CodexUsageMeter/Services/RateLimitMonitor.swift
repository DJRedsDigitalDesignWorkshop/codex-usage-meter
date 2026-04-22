@preconcurrency import Combine
import Foundation

@MainActor
final class RateLimitMonitor: ObservableObject {
    @Published private(set) var snapshot: CodexRateLimitSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let scanner: CodexSessionScanner
    private var refreshTask: Task<Void, Never>?
    private var timerCancellable: AnyCancellable?

    init(scanner: CodexSessionScanner = CodexSessionScanner()) {
        self.scanner = scanner
        reloadTimer()
        refresh()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }

            isRefreshing = true
            defer { isRefreshing = false }

            do {
                let directoryURL = AppPreferences.sessionsDirectoryURL
                let latest = try scanner.latestSnapshot(in: directoryURL)
                snapshot = latest
                errorMessage = nil
            } catch {
                snapshot = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func reloadTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(
            every: AppPreferences.refreshInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.refresh()
        }
    }
}

enum AppPreferences {
    static let sessionsDirectoryKey = "sessionsDirectoryPath"
    static let refreshIntervalKey = "refreshInterval"

    static var sessionsDirectoryURL: URL {
        if let storedPath = UserDefaults.standard.string(forKey: sessionsDirectoryKey),
           !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: storedPath, isDirectory: true)
        }

        return defaultSessionsDirectoryURL
    }

    static var refreshInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: refreshIntervalKey)
        return value > 0 ? value : 15
    }

    static var defaultSessionsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}
