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
        #expect(snapshot.activityStatus == .done)
        #expect(snapshot.needsPermission == false)
        #expect(snapshot.sourceFile.lastPathComponent == "rollout-newer.jsonl")
    }

    @Test
    func derivesWorkingAndPermissionStatesFromSessionEvents() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("rollout-status.jsonl")

        try """
        {"timestamp":"2026-04-22T14:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-22T14:00:01.000Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","arguments":"{\\"sandbox_permissions\\":\\"require_escalated\\",\\"justification\\":\\"Need approval\\"}"}}
        {"timestamp":"2026-04-22T14:00:02.000Z","payload":{"rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":1776870000},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1777470000},"plan_type":"plus"}}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.activityStatus == .working)
        #expect(snapshot.needsPermission == true)
    }

    @Test
    func prefersAnyActiveRecentSessionForStatusIndicators() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirectory = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("22", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let newestCompletedFile = sessionsDirectory.appendingPathComponent("rollout-newest-complete.jsonl")
        let olderActiveFile = sessionsDirectory.appendingPathComponent("rollout-older-active.jsonl")

        try """
        {"timestamp":"2026-04-22T14:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-22T14:00:03.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        {"timestamp":"2026-04-22T14:00:04.000Z","payload":{"rate_limits":{"primary":{"used_percent":20.0,"window_minutes":300,"resets_at":1776870000},"secondary":{"used_percent":9.0,"window_minutes":10080,"resets_at":1777470000},"plan_type":"plus"}}}
        """.write(to: newestCompletedFile, atomically: true, encoding: .utf8)

        try """
        {"timestamp":"2026-04-22T13:59:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}
        {"timestamp":"2026-04-22T13:59:05.000Z","type":"response_item","payload":{"type":"function_call","call_id":"call-2","arguments":"{\\"sandbox_permissions\\":\\"require_escalated\\",\\"justification\\":\\"Need approval\\"}"}}
        {"timestamp":"2026-04-22T13:59:06.000Z","payload":{"rate_limits":{"primary":{"used_percent":21.0,"window_minutes":300,"resets_at":1776870001},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1777470001},"plan_type":"plus"}}}
        """.write(to: olderActiveFile, atomically: true, encoding: .utf8)

        let now = Date()
        try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: newestCompletedFile.path)
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-1)], ofItemAtPath: olderActiveFile.path)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let status = try scanner.latestSessionStatus(in: root)

        #expect(status.activityStatus == .working)
        #expect(status.needsPermission == true)
    }

    @Test
    func expiresStaleUnmatchedTaskAndPermissionSignals() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("rollout-stale-status.jsonl")

        try """
        {"timestamp":"2026-04-22T14:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-22T14:00:01.000Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","arguments":"{\\"sandbox_permissions\\":\\"require_escalated\\",\\"justification\\":\\"Need approval\\"}"}}
        {"timestamp":"2026-04-22T14:00:02.000Z","payload":{"rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":1776870000},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1777470000},"plan_type":"plus"}}}
        """.write(to: file, atomically: true, encoding: .utf8)

        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: file.path)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.activityStatus == .done)
        #expect(snapshot.needsPermission == false)
    }

    @Test
    func prefersFreshestRateLimitTimestampAcrossRecentFiles() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirectory = root
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("23", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let newerModifiedFile = sessionsDirectory.appendingPathComponent("rollout-newer-modified.jsonl")
        let olderModifiedFile = sessionsDirectory.appendingPathComponent("rollout-older-modified.jsonl")

        try """
        {"timestamp":"2026-04-23T14:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1776978000},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":1777578000},"plan_type":"plus"}}}
        """.write(to: newerModifiedFile, atomically: true, encoding: .utf8)

        try """
        {"timestamp":"2026-04-23T14:05:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1776978300},"secondary":{"used_percent":8.0,"window_minutes":10080,"resets_at":1777578300},"plan_type":"plus"}}}
        """.write(to: olderModifiedFile, atomically: true, encoding: .utf8)

        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newerModifiedFile.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: olderModifiedFile.path)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.primary.usedPercent == 10.0)
        #expect(snapshot.capturedAt == ISO8601DateFormatter().date(from: "2026-04-23T14:05:00Z"))
    }

    @Test
    func keepsWorkingStateWhenRequestedTailWouldMissTaskStart() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("rollout-large-active.jsonl")
        let filler = String(repeating: #"{"timestamp":"2026-04-23T14:00:01.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"filler"}],"phase":"commentary"}}"# + "\n", count: 4_000)

        try (
            """
            {"timestamp":"2026-04-23T14:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
            """
            + filler
        ).write(to: file, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let status = try scanner.latestSessionStatus(in: root, tailByteCount: 512)

        #expect(status.activityStatus == .working)
    }

    @Test
    func parsesPermissionRequestsFromFormattedArgumentsJson() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent("rollout-formatted-permission.jsonl")

        try """
        {"timestamp":"2026-04-23T14:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T14:00:01.000Z","type":"response_item","payload":{"type":"function_call","call_id":"call-1","arguments":"{\\n  \\"sandbox_permissions\\" : \\"require_escalated\\",\\n  \\"justification\\" : \\"Need approval\\"\\n}"}}
        {"timestamp":"2026-04-23T14:00:02.000Z","payload":{"rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":1776870000},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1777470000},"plan_type":"plus"}}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.needsPermission == true)
        #expect(snapshot.activityStatus == .working)
    }

    @Test
    func prefersTopLevelSnapshotOverNewerSubagentSnapshot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let topLevelFile = root.appendingPathComponent("rollout-top-level.jsonl")
        let subagentFile = root.appendingPathComponent("rollout-subagent.jsonl")

        try """
        {"type":"session_meta","payload":{"id":"top-level","cwd":"/tmp/project","source":"vscode"}}
        {"timestamp":"2026-04-23T14:00:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":43.0,"window_minutes":300,"resets_at":1776978000},"secondary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1777578000},"plan_type":"plus"}}}
        """.write(to: topLevelFile, atomically: true, encoding: .utf8)

        try """
        {"type":"session_meta","payload":{"id":"subagent","cwd":"/tmp/project","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}
        {"timestamp":"2026-04-23T14:01:00.000Z","payload":{"rate_limits":{"primary":{"used_percent":86.0,"window_minutes":300,"resets_at":1776978060},"secondary":{"used_percent":35.0,"window_minutes":10080,"resets_at":1777578060},"plan_type":"plus"}}}
        """.write(to: subagentFile, atomically: true, encoding: .utf8)

        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: topLevelFile.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: subagentFile.path)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.primary.usedPercent == 43.0)
        #expect(snapshot.secondary?.usedPercent == 28.0)
        #expect(snapshot.sourceFile.lastPathComponent == "rollout-top-level.jsonl")
    }

    @Test
    func ignoresSubagentStatusWhenTopLevelSessionsExist() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let topLevelFile = root.appendingPathComponent("rollout-top-level-done.jsonl")
        let subagentFile = root.appendingPathComponent("rollout-subagent-working.jsonl")

        try """
        {"type":"session_meta","payload":{"id":"top-level","cwd":"/tmp/project","source":"vscode"}}
        {"timestamp":"2026-04-23T14:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T14:00:01.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        {"timestamp":"2026-04-23T14:00:02.000Z","payload":{"rate_limits":{"primary":{"used_percent":43.0,"window_minutes":300,"resets_at":1776978000},"secondary":{"used_percent":28.0,"window_minutes":10080,"resets_at":1777578000},"plan_type":"plus"}}}
        """.write(to: topLevelFile, atomically: true, encoding: .utf8)

        try """
        {"type":"session_meta","payload":{"id":"subagent","cwd":"/tmp/project","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}
        {"timestamp":"2026-04-23T14:01:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}
        {"timestamp":"2026-04-23T14:01:01.000Z","type":"response_item","payload":{"type":"function_call","call_id":"call-2","arguments":"{\\"sandbox_permissions\\":\\"require_escalated\\",\\"justification\\":\\"Need approval\\"}"}}
        {"timestamp":"2026-04-23T14:01:02.000Z","payload":{"rate_limits":{"primary":{"used_percent":86.0,"window_minutes":300,"resets_at":1776978060},"secondary":{"used_percent":35.0,"window_minutes":10080,"resets_at":1777578060},"plan_type":"plus"}}}
        """.write(to: subagentFile, atomically: true, encoding: .utf8)

        let now = Date()
        try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: topLevelFile.path)
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(1)], ofItemAtPath: subagentFile.path)

        let scanner = CodexSessionScanner(fileManager: fileManager)
        let snapshot = try scanner.latestSnapshot(in: root)

        #expect(snapshot.activityStatus == .done)
        #expect(snapshot.needsPermission == false)
        #expect(snapshot.sourceFile.lastPathComponent == "rollout-top-level-done.jsonl")
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
