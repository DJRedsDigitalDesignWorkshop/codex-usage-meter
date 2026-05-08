import Foundation

struct CodexRPCUsageClient {
    enum RPCError: LocalizedError {
        case codexBinaryMissing
        case timedOut
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .codexBinaryMissing:
                return "Codex app-server is not available. Install or open Codex, then refresh."
            case .timedOut:
                return "Codex app-server did not return rate limits in time."
            case .invalidResponse:
                return "Codex app-server returned rate limits in an unexpected format."
            }
        }
    }

    private struct RPCResponse: Decodable {
        struct Result: Decodable {
            let rateLimits: RateLimits?
        }

        let id: Int?
        let result: Result?
    }

    private struct RateLimits: Decodable {
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int?
            let resetsAt: TimeInterval?
        }

        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    private final class RPCState: @unchecked Sendable {
        private let lock = NSLock()
        private let decoder = JSONDecoder()
        private var bufferedOutput = Data()
        private var decodedRateLimits: RateLimits?

        let semaphore = DispatchSemaphore(value: 0)

        var rateLimits: RateLimits? {
            lock.lock()
            defer { lock.unlock() }
            return decodedRateLimits
        }

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }

            bufferedOutput.append(data)

            while let newline = bufferedOutput.firstIndex(of: 0x0A) {
                let line = Data(bufferedOutput[..<newline])
                bufferedOutput.removeSubrange(...newline)

                if let response = try? decoder.decode(RPCResponse.self, from: line),
                   response.id == 2,
                   let rateLimits = response.result?.rateLimits {
                    decodedRateLimits = rateLimits
                    semaphore.signal()
                }
            }
        }
    }

    var timeout: TimeInterval = 6

    func latestSnapshot(status: CodexSessionStatus?) throws -> CodexRateLimitSnapshot {
        let codexBinary = try resolveCodexBinary()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let state = RPCState()

        process.executableURL = URL(fileURLWithPath: codexBinary)
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            state.append(data)
        }

        error.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        try process.run()

        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex-usage-meter", "version": appVersionString()]]], to: input)
        try send(["method": "initialized", "params": [:]], to: input)
        try send(["id": 2, "method": "account/rateLimits/read", "params": [:]], to: input)

        let waitResult = state.semaphore.wait(timeout: .now() + timeout)

        output.fileHandleForReading.readabilityHandler = nil
        error.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
        }

        guard waitResult == .success else {
            throw RPCError.timedOut
        }

        guard let rateLimits = state.rateLimits,
              let primary = rateLimits.primary else {
            throw RPCError.invalidResponse
        }

        return CodexRateLimitSnapshot(
            capturedAt: Date(),
            planType: rateLimits.planType ?? "unknown",
            primary: makeWindow(from: primary),
            secondary: rateLimits.secondary.map(makeWindow(from:)),
            activityStatus: status?.activityStatus ?? .done,
            needsPermission: status?.needsPermission ?? false,
            sourceFile: URL(fileURLWithPath: codexBinary)
        )
    }

    private func makeWindow(from window: RateLimits.Window) -> CodexRateLimitSnapshot.Window {
        CodexRateLimitSnapshot.Window(
            usedPercent: window.usedPercent,
            windowMinutes: window.windowDurationMins ?? 0,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }

    private func send(_ object: [String: Any], to pipe: Pipe) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func resolveCodexBinary() throws -> String {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        throw RPCError.codexBinaryMissing
    }

    private func appVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
