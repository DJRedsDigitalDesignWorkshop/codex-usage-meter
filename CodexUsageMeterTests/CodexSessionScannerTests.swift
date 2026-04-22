import Foundation
import Testing
import CodexUsageMeter

struct CodexSessionScannerTests {
    @Test
    func findsLatestRateLimitSnapshotFromNewestSessionFile() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirectory = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("20", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let olderFile = sessionsDirectory.appendingPathComponent("rollout-older.jsonl")
        let newerFile = sessionsDirectory.appendingPathComponent("rollout-newer.jsonl")

        try """
        {"timestamp":"2026-04-20T16:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1776700000},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":1777300000},"plan_type":"plus"}}}
        """.write(to: olderFile, atomically: true, encoding: .utf8)

        try """
        {"timestamp":"2026-04-20T18:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1776710000},"secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1777310000},"plan_type":"pro"}}}
        """.write(to: newerFile, atomically: true, encoding: .utf8)

        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: olderFile.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newerFile.path)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.planType == "pro")
        #expect(snapshot.primary.usedPercent == 12.0)
        #expect(snapshot.secondary?.usedPercent == 7.0)
        #expect(snapshot.sourceFile.lastPathComponent == "rollout-newer.jsonl")
    }

    @Test
    func throwsHelpfulErrorWhenNoSnapshotsExist() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let scanner = CodexSessionScanner(fileManager: fileManager)

        #expect(throws: CodexSessionScanner.ScannerError.self) {
            try scanner.latestSnapshot(in: root)
        }
    }
}
