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
        titleText
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
        .help(helpText)
    }

    private var titleText: Text {
        guard let snapshot else {
            return Text(Image(systemName: "gauge.with.dots.needle.0percent")) + Text(" --% --%")
        }

        let primary = snapshot.primary.remainingPercentString
        let secondary = snapshot.secondary?.remainingPercentString ?? "--%"
        return Text(Image(systemName: symbolName))
            + Text(" \(primary) \(secondary)")
            + Text(" ")
            + Text(Image(systemName: "capsule.portrait.fill"))
            + Text(snapshot.activityStatus == .working ? "WORK" : "DONE")
            + Text(" ")
            + Text(Image(systemName: snapshot.needsPermission ? "octagon.fill" : "octagon"))
            + Text(snapshot.needsPermission ? "?" : "")
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
        let activity = snapshot.activityStatus == .working ? "working" : "done"
        let permission = snapshot.needsPermission ? "needs permission" : "does not need permission"
        return "Remaining Codex limits: \(snapshot.primary.remainingPercentString) short window, \(secondary) long window. Codex is \(activity) and currently \(permission)."
    }
}
