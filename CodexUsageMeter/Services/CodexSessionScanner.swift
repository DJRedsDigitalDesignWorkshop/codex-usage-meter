import Foundation

public struct CodexSessionScanner {
    private struct SessionIndicators {
        let activityStatus: CodexRateLimitSnapshot.ActivityStatus
        let needsPermission: Bool
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
        let latestIndicators = try candidateFiles.first.map { try sessionIndicators(inFile: $0, tailByteCount: tailByteCount) }

        for fileURL in candidateFiles {
            let indicators = if fileURL == candidateFiles.first {
                latestIndicators ?? SessionIndicators(activityStatus: .done, needsPermission: false)
            } else {
                try sessionIndicators(inFile: fileURL, tailByteCount: tailByteCount)
            }

            if let snapshot = try latestSnapshot(
                inFile: fileURL,
                tailByteCount: tailByteCount,
                indicators: indicators
            ) {
                return snapshot
            }
        }

        throw ScannerError.noSnapshotsFound(sessionsDirectory)
    }

    private func recentSessionFiles(in directory: URL, limit: Int) throws -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var files: [(url: URL, modifiedAt: Date)] = []

        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            guard item.lastPathComponent.hasPrefix("rollout-") else { continue }

            let resourceValues = try item.resourceValues(forKeys: Set(keys))
            guard resourceValues.isRegularFile == true else { continue }

            files.append((item, resourceValues.contentModificationDate ?? .distantPast))
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.url)
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
        guard let rawText = String(data: data, encoding: .utf8) else {
            return SessionIndicators(activityStatus: .done, needsPermission: false)
        }

        var latestActivityStatus = CodexRateLimitSnapshot.ActivityStatus.done
        var pendingApprovalCalls: Set<String> = []

        for line in rawText.split(separator: "\n") {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let recordType = object["type"] as? String
            else {
                continue
            }

            let payload = object["payload"] as? [String: Any]

            if recordType == "event_msg", let payloadType = payload?["type"] as? String {
                switch payloadType {
                case "task_started":
                    latestActivityStatus = .working
                case "task_complete":
                    latestActivityStatus = .done
                default:
                    break
                }
            }

            if recordType == "response_item", let payloadType = payload?["type"] as? String {
                switch payloadType {
                case "function_call":
                    guard let callID = payload?["call_id"] as? String else { continue }
                    let arguments = payload?["arguments"] as? String ?? ""
                    if arguments.contains("\"sandbox_permissions\":\"require_escalated\"") ||
                        arguments.contains("\"sandbox_permissions\": \"require_escalated\"") {
                        pendingApprovalCalls.insert(callID)
                    }
                case "function_call_output":
                    if let callID = payload?["call_id"] as? String {
                        pendingApprovalCalls.remove(callID)
                    }
                default:
                    break
                }
            }
        }

        return SessionIndicators(
            activityStatus: latestActivityStatus,
            needsPermission: !pendingApprovalCalls.isEmpty
        )
    }

    private func tailData(for fileURL: URL, byteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let offset = fileSize > UInt64(byteCount) ? fileSize - UInt64(byteCount) : 0
        try handle.seek(toOffset: offset)
        return try handle.readToEnd() ?? Data()
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
