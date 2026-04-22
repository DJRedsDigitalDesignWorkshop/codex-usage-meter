import SwiftUI

@main
struct CodexUsageMeterApp: App {
    @StateObject private var monitor = RateLimitMonitor()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(monitor: monitor)
        } label: {
            StatusBarLabelView(snapshot: monitor.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor)
                .frame(width: 460)
        }
    }
}

private struct StatusBarLabelView: View {
    let snapshot: CodexRateLimitSnapshot?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .imageScale(.small)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .help(helpText)
    }

    private var title: String {
        guard let snapshot else { return "--% --%" }

        let primary = snapshot.primary.remainingPercentString
        let secondary = snapshot.secondary?.remainingPercentString ?? "--%"
        return "\(primary) \(secondary)"
    }

    private var symbolName: String {
        guard let snapshot else { return "gauge.with.dots.needle.0percent" }

        switch snapshot.primary.usedPercent {
        case ..<50:
            return "gauge.with.dots.needle.33percent"
        case ..<80:
            return "gauge.with.dots.needle.67percent"
        default:
            return "exclamationmark.gauge"
        }
    }

    private var helpText: String {
        guard let snapshot else {
            return "No Codex rate-limit snapshot found yet."
        }

        let secondary = snapshot.secondary?.remainingPercentString ?? "--%"
        return "Remaining Codex limits: \(snapshot.primary.remainingPercentString) short window, \(secondary) long window."
    }
}
