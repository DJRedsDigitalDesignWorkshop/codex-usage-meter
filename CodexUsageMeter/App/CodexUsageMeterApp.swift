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

            ActivityBadge(status: snapshot?.activityStatus ?? .done)
            PermissionBadge(needsPermission: snapshot?.needsPermission ?? false)
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
        let activity = snapshot.activityStatus == .working ? "working" : "done"
        let permission = snapshot.needsPermission ? "needs permission" : "does not need permission"
        return "Remaining Codex limits: \(snapshot.primary.remainingPercentString) short window, \(secondary) long window. Codex is \(activity) and currently \(permission)."
    }
}

private struct ActivityBadge: View {
    let status: CodexRateLimitSnapshot.ActivityStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule(style: .continuous))
    }

    private var foregroundColor: Color {
        status == .working ? .orange : .green
    }

    private var backgroundColor: Color {
        status == .working ? Color.orange.opacity(0.16) : Color.green.opacity(0.16)
    }
}

private struct PermissionBadge: View {
    let needsPermission: Bool

    var body: some View {
        ZStack {
            Image(systemName: "octagon.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(needsPermission ? Color.red.opacity(0.9) : Color.secondary.opacity(0.35))

            Text("?")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: -0.25)
        }
    }
}
