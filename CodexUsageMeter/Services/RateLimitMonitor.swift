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
    private var statusTimerCancellable: AnyCancellable?

    init(scanner: CodexSessionScanner = CodexSessionScanner()) {
        self.scanner = scanner
        reloadTimer()
        reloadStatusTimer()
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

    func reloadStatusTimer() {
        statusTimerCancellable?.cancel()
        statusTimerCancellable = Timer.publish(
            every: AppPreferences.statusRefreshInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func refreshStatus() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                let directoryURL = AppPreferences.sessionsDirectoryURL
                let status = try scanner.latestSessionStatus(in: directoryURL)

                if let snapshot {
                    self.snapshot = CodexRateLimitSnapshot(
                        capturedAt: snapshot.capturedAt,
                        planType: snapshot.planType,
                        primary: snapshot.primary,
                        secondary: snapshot.secondary,
                        activityStatus: status.activityStatus,
                        needsPermission: status.needsPermission,
                        estimatedTokensPerSecond: status.estimatedTokensPerSecond,
                        sourceFile: snapshot.sourceFile
                    )
                } else {
                    refresh()
                }
            } catch {
                // Keep the last known usage snapshot if status-only polling fails transiently.
            }
        }
    }
}

enum AppPreferences {
    static let sessionsDirectoryKey = "sessionsDirectoryPath"
    static let refreshIntervalKey = "refreshInterval"
    static let defaultRefreshInterval: TimeInterval = 60
    static let allowedRefreshIntervals: [TimeInterval] = [30, 60, 120, 300]
    static let statusRefreshInterval: TimeInterval = 10

    static var sessionsDirectoryURL: URL {
        if let storedPath = UserDefaults.standard.string(forKey: sessionsDirectoryKey),
           !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: storedPath, isDirectory: true)
        }

        return defaultSessionsDirectoryURL
    }

    static var refreshInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: refreshIntervalKey)
        guard value > 0 else { return defaultRefreshInterval }
        return allowedRefreshIntervals.contains(value) ? value : defaultRefreshInterval
    }

    static var defaultSessionsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}
