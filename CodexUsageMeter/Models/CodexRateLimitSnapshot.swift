import Foundation

public struct CodexRateLimitSnapshot: Equatable, Sendable {
    public enum ActivityStatus: Equatable, Sendable {
        case working
        case done

        public var label: String {
            switch self {
            case .working:
                return "Thinking"
            case .done:
                return "Done"
            }
        }
    }

    public struct Window: Equatable, Sendable {
        public let usedPercent: Double
        public let windowMinutes: Int
        public let resetsAt: Date

        public var remainingPercent: Double {
            max(0, 100 - usedPercent)
        }

        public var remainingPercentString: String {
            "\(Int(remainingPercent.rounded()))%"
        }

        public var progressValue: Double {
            min(max(remainingPercent / 100, 0), 1)
        }

        public var windowTitle: String {
            if windowMinutes == 300 {
                return "5-hour window"
            }

            if windowMinutes == 10080 {
                return "Weekly window"
            }

            if windowMinutes % 60 == 0 {
                return "\(windowMinutes / 60)-hour window"
            }

            return "\(windowMinutes)-minute window"
        }
    }

    public let capturedAt: Date
    public let planType: String
    public let primary: Window
    public let secondary: Window?
    public let activityStatus: ActivityStatus
    public let needsPermission: Bool
    public let sourceFile: URL

    public var freshnessDescription: String {
        Self.relativeDescription(for: capturedAt)
    }

    public static func relativeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
