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
                let latest = try AppPreferences.withSecurityScopedAccess(to: directoryURL) {
                    try scanner.latestSnapshot(in: directoryURL)
                }
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
    static let sessionsDirectoryBookmarkKey = "sessionsDirectoryBookmark"
    static let refreshIntervalKey = "refreshInterval"

    static var sessionsDirectoryURL: URL {
        if let resolvedURL = resolvedBookmarkURL() {
            return resolvedURL
        }

        if let storedPath = UserDefaults.standard.string(forKey: sessionsDirectoryKey),
           !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: storedPath, isDirectory: true)
        }

        return defaultSessionsDirectoryURL
    }

    static var usesSecurityScopedBookmark: Bool {
        UserDefaults.standard.data(forKey: sessionsDirectoryBookmarkKey) != nil
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

    static func restoreDefaultSessionsDirectory() {
        UserDefaults.standard.removeObject(forKey: sessionsDirectoryBookmarkKey)
        UserDefaults.standard.set(defaultSessionsDirectoryURL.path, forKey: sessionsDirectoryKey)
    }

    static func storeSessionsDirectoryAccess(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(bookmark, forKey: sessionsDirectoryBookmarkKey)
        UserDefaults.standard.set(url.path, forKey: sessionsDirectoryKey)
    }

    static func withSecurityScopedAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try body()
    }

    private static func resolvedBookmarkURL() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: sessionsDirectoryBookmarkKey) else {
            return nil
        }

        var isStale = false

        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            try? storeSessionsDirectoryAccess(url)
        }

        return url
    }
}
