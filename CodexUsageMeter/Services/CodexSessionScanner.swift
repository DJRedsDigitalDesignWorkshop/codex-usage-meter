import Foundation

public struct CodexSessionStatus: Equatable {
    public let activityStatus: CodexRateLimitSnapshot.ActivityStatus
    public let needsPermission: Bool
}

public struct CodexSessionScanner {
    private static let minimumIndicatorsTailByteCount = 8_388_608
    private static let sessionMetaProbeByteCount = 16_384
    private static let staleActivityInterval: TimeInterval = 120
    private static let stalePermissionInterval: TimeInterval = 120
    private static let recentModificationGraceInterval: TimeInterval = 15

    private struct SessionIndicators {
        let activityStatus: CodexRateLimitSnapshot.ActivityStatus
        let needsPermission: Bool
    }

    private struct SessionFile {
        let url: URL
        let modifiedAt: Date
        let isSubagent: Bool
    }

    public enum ScannerError: LocalizedError {
        case sessionsDirectoryMissing(URL)
        case noSnapshotsFound(URL)

        public var errorDescription: String? {
            switch self {
            case let .sessionsDirectoryMissing(url):
                return "The Codex sessions folder does not exist at \(url.path)."
            case let .noSnapshotsFound(url):
                return "No Codex rate-limit snapshots were found in \(url.path). Run a Codex session once and refresh."
            }
        }
    }

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let fractionalTimestampFormatter: ISO8601DateFormatter
    private let basicTimestampFormatter: ISO8601DateFormatter

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let value = try container.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = fractional.date(from: value) {
                return date
            }

            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]

            if let date = basic.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: try container.singleValueContainer(),
                debugDescription: "Unsupported timestamp format: \(value)"
            )
        }
        self.decoder = decoder

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalTimestampFormatter = fractionalFormatter

        let basicFormatter = ISO8601DateFormatter()
        basicFormatter.formatOptions = [.withInternetDateTime]
        self.basicTimestampFormatter = basicFormatter
    }

    public func latestSnapshot(
        in sessionsDirectory: URL,
        maximumFilesToInspect: Int = 40,
        tailByteCount: Int = 262_144
    ) throws -> CodexRateLimitSnapshot {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            throw ScannerError.sessionsDirectoryMissing(sessionsDirectory)
        }

        let candidateFiles = try recentSessionFiles(in: sessionsDirectory, limit: maximumFilesToInspect)
        let snapshotFiles = preferredSnapshotFiles(from: candidateFiles)
        let aggregateIndicators = try aggregateSessionIndicators(
            inFiles: snapshotFiles,
            tailByteCount: max(tailByteCount, Self.minimumIndicatorsTailByteCount)
        )

        var freshestSnapshot: CodexRateLimitSnapshot?

        for fileURL in snapshotFiles {
            if let snapshot = try latestSnapshot(
                inFile: fileURL,
                tailByteCount: tailByteCount,
                indicators: aggregateIndicators
            ) {
                if let currentFreshest = freshestSnapshot {
                    if snapshot.capturedAt > currentFreshest.capturedAt {
                        freshestSnapshot = snapshot
                    }
                } else {
                    freshestSnapshot = snapshot
                }
            }
        }

        if let freshestSnapshot {
            return freshestSnapshot
        }

        throw ScannerError.noSnapshotsFound(sessionsDirectory)
    }

    public func latestSessionStatus(
        in sessionsDirectory: URL,
        maximumFilesToInspect: Int = 40,
        tailByteCount: Int = 262_144
    ) throws -> CodexSessionStatus {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            throw ScannerError.sessionsDirectoryMissing(sessionsDirectory)
        }

        let candidateFiles = try recentSessionFiles(in: sessionsDirectory, limit: maximumFilesToInspect)
        guard !candidateFiles.isEmpty else {
            throw ScannerError.noSnapshotsFound(sessionsDirectory)
        }

        let statusFiles = preferredSnapshotFiles(from: candidateFiles)
        let indicators = try aggregateSessionIndicators(
            inFiles: statusFiles,
            tailByteCount: max(tailByteCount, Self.minimumIndicatorsTailByteCount)
        )
        return CodexSessionStatus(
            activityStatus: indicators.activityStatus,
            needsPermission: indicators.needsPermission
        )
    }

    private func recentSessionFiles(in directory: URL, limit: Int) throws -> [SessionFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var files: [SessionFile] = []

        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            guard item.lastPathComponent.hasPrefix("rollout-") else { continue }

            let resourceValues = try item.resourceValues(forKeys: Set(keys))
            guard resourceValues.isRegularFile == true else { continue }

            files.append(
                SessionFile(
                    url: item,
                    modifiedAt: resourceValues.contentModificationDate ?? .distantPast,
                    isSubagent: try isSubagentSessionFile(item)
                )
            )
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }

    private func latestSnapshot(
        inFile fileURL: URL,
        tailByteCount: Int,
        indicators: SessionIndicators
    ) throws -> CodexRateLimitSnapshot? {
        let data = try tailData(for: fileURL, byteCount: tailByteCount)
        guard let rawText = String(data: data, encoding: .utf8) else { return nil }

        for line in rawText.split(separator: "\n").reversed() {
            guard line.contains("\"rate_limits\"") else { continue }
            guard let event = try? decoder.decode(SessionEvent.self, from: Data(line.utf8)) else { continue }
            guard let rateLimits = event.payload?.rateLimits else { continue }
            guard let primary = rateLimits.primary else { continue }

            return CodexRateLimitSnapshot(
                capturedAt: event.timestamp ?? .distantPast,
                planType: rateLimits.planType ?? "unknown",
                primary: .init(
                    usedPercent: primary.usedPercent,
                    windowMinutes: primary.windowMinutes,
                    resetsAt: Date(timeIntervalSince1970: primary.resetsAt)
                ),
                secondary: rateLimits.secondary.map {
                    .init(
                        usedPercent: $0.usedPercent,
                        windowMinutes: $0.windowMinutes,
                        resetsAt: Date(timeIntervalSince1970: $0.resetsAt)
                    )
                },
                activityStatus: indicators.activityStatus,
                needsPermission: indicators.needsPermission,
                sourceFile: fileURL
            )
        }

        return nil
    }

    private func sessionIndicators(inFile fileURL: URL, tailByteCount: Int) throws -> SessionIndicators {
        let data = try tailData(for: fileURL, byteCount: tailByteCount)
        let rawText = String(decoding: data, as: UTF8.self)
        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

        var latestActivityStatus = CodexRateLimitSnapshot.ActivityStatus.done
        var openTurnIDs: [String: Date] = [:]
        var pendingApprovalCalls: [String: Date] = [:]
        var sawActivityEvent = false

        for line in rawText.split(separator: "\n") {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let recordType = object["type"] as? String
            else {
                continue
            }

            let payload = object["payload"] as? [String: Any]
            let eventAt = eventDate(from: object) ?? modifiedAt

            if recordType == "event_msg", let payloadType = payload?["type"] as? String {
                switch payloadType {
                case "task_started":
                    sawActivityEvent = true
                    let turnID = payload?["turn_id"] as? String ?? "__unknown_turn__"
                    openTurnIDs[turnID] = eventAt
                    latestActivityStatus = .working
                case "task_complete":
                    sawActivityEvent = true
                    if let turnID = payload?["turn_id"] as? String {
                        openTurnIDs.removeValue(forKey: turnID)
                    } else {
                        openTurnIDs.removeAll()
                    }
                    latestActivityStatus = openTurnIDs.isEmpty ? .done : .working
                default:
                    break
                }
            }

            if recordType == "response_item", let payloadType = payload?["type"] as? String {
                switch payloadType {
                case "function_call":
                    guard let callID = payload?["call_id"] as? String else { continue }
                    let arguments = payload?["arguments"] as? String ?? ""
                    if requiresEscalatedSandbox(arguments: arguments) {
                        pendingApprovalCalls[callID] = eventAt
                    }
                case "function_call_output":
                    if let callID = payload?["call_id"] as? String {
                        pendingApprovalCalls.removeValue(forKey: callID)
                    }
                default:
                    break
                }
            }
        }

        let hasFreshOpenTurn = openTurnIDs.values.contains {
            isFresh(eventAt: $0, modifiedAt: modifiedAt, staleInterval: Self.staleActivityInterval)
        }
        let hasFreshPendingApproval = pendingApprovalCalls.values.contains {
            isFresh(eventAt: $0, modifiedAt: modifiedAt, staleInterval: Self.stalePermissionInterval)
        }

        if hasFreshOpenTurn {
            latestActivityStatus = .working
        } else if !sawActivityEvent && isRecentlyModified(modifiedAt) {
            latestActivityStatus = .working
        } else if latestActivityStatus == .working {
            latestActivityStatus = .done
        }

        return SessionIndicators(
            activityStatus: latestActivityStatus,
            needsPermission: hasFreshPendingApproval
        )
    }

    private func aggregateSessionIndicators(inFiles fileURLs: [URL], tailByteCount: Int) throws -> SessionIndicators {
        var mostRecentIndicators = SessionIndicators(
            activityStatus: .done,
            needsPermission: false
        )

        for (index, fileURL) in fileURLs.enumerated() {
            let indicators = try sessionIndicators(inFile: fileURL, tailByteCount: tailByteCount)

            if index == 0 {
                mostRecentIndicators = indicators
            }

            if indicators.needsPermission {
                return SessionIndicators(
                    activityStatus: .working,
                    needsPermission: true
                )
            }

            if indicators.activityStatus == .working {
                return SessionIndicators(
                    activityStatus: .working,
                    needsPermission: false
                )
            }
        }

        return mostRecentIndicators
    }

    private func preferredSnapshotFiles(from files: [SessionFile]) -> [URL] {
        let topLevelFiles = files.filter { !$0.isSubagent }.map(\.url)
        return topLevelFiles.isEmpty ? files.map(\.url) : topLevelFiles
    }

    private func isSubagentSessionFile(_ fileURL: URL) throws -> Bool {
        let data = try headData(for: fileURL, byteCount: Self.sessionMetaProbeByteCount)
        let rawText = String(decoding: data, as: UTF8.self)

        for line in rawText.split(separator: "\n") {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "session_meta",
                let payload = object["payload"] as? [String: Any]
            else {
                continue
            }

            let source = payload["source"] as? [String: Any]
            return source?["subagent"] != nil
        }

        return false
    }

    private func tailData(for fileURL: URL, byteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let offset = fileSize > UInt64(byteCount) ? fileSize - UInt64(byteCount) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()

        guard offset > 0 else { return data }
        guard let newlineIndex = data.firstIndex(of: 0x0A) else { return Data() }
        let nextIndex = data.index(after: newlineIndex)
        return Data(data[nextIndex...])
    }

    private func headData(for fileURL: URL, byteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: byteCount) ?? Data()
        return data
    }

    private func requiresEscalatedSandbox(arguments: String) -> Bool {
        guard let data = arguments.data(using: .utf8) else {
            return false
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sandboxPermissions = object["sandbox_permissions"] as? String {
            return sandboxPermissions == "require_escalated"
        }

        return arguments.contains("\"sandbox_permissions\":\"require_escalated\"") ||
            arguments.contains("\"sandbox_permissions\": \"require_escalated\"")
    }

    private func eventDate(from object: [String: Any]) -> Date? {
        guard let timestamp = object["timestamp"] as? String else { return nil }
        return fractionalTimestampFormatter.date(from: timestamp) ?? basicTimestampFormatter.date(from: timestamp)
    }

    private func isFresh(eventAt: Date, modifiedAt: Date, staleInterval: TimeInterval) -> Bool {
        Date().timeIntervalSince(eventAt) <= staleInterval || isRecentlyModified(modifiedAt)
    }

    private func isRecentlyModified(_ modifiedAt: Date) -> Bool {
        Date().timeIntervalSince(modifiedAt) < Self.recentModificationGraceInterval
    }
}

private struct SessionEvent: Decodable {
    struct Payload: Decodable {
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }

    struct RateLimits: Decodable {
        struct Window: Decodable {
            let usedPercent: Double
            let windowMinutes: Int
            let resetsAt: TimeInterval

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case windowMinutes = "window_minutes"
                case resetsAt = "resets_at"
            }
        }

        let primary: Window?
        let secondary: Window?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case primary
            case secondary
            case planType = "plan_type"
        }
    }

    let timestamp: Date?
    let payload: Payload?
}
