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
            usageSummary

            if let snapshot {
                ActivityBadgeView(status: snapshot.activityStatus)
                PermissionBadgeView(needsPermission: snapshot.needsPermission)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .fixedSize()
        .help(helpText)
    }

    private var usageSummary: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .imageScale(.small)

            Text(usageText)
        }
    }

    private var usageText: String {
        guard let snapshot else {
            return "--% --%"
        }

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

private struct ActivityBadgeView: View {
    let status: CodexRateLimitSnapshot.ActivityStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 14, height: 14)
                    .background(.white.opacity(0.92), in: Circle())
            } else {
                Image(systemName: "octagon.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            Text(status.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(background, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(border, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
        .accessibilityLabel(status == .working ? "Codex thinking" : "Codex done")
    }

    private var background: LinearGradient {
        LinearGradient(
            colors: [
                accentColor.opacity(status == .done ? 0.44 : 0.26),
                accentColor.opacity(status == .done ? 0.28 : 0.16)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var border: Color {
        accentColor.opacity(status == .done ? 0.5 : 0.3)
    }

    private var accentColor: Color {
        status == .done ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed)
    }

    private var textColor: Color {
        status == .done ? .white.opacity(0.95) : Color(nsColor: .systemRed).opacity(0.95)
    }
}

private struct PermissionBadgeView: View {
    let needsPermission: Bool

    var body: some View {
        ZStack {
            Image(systemName: needsPermission ? "octagon.fill" : "octagon")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(symbolColor)

            Text("?")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(questionColor)
                .offset(y: -0.5)
        }
        .frame(width: 18, height: 18)
        .padding(2)
        .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(border, lineWidth: 0.8)
        }
        .accessibilityLabel(needsPermission ? "Codex needs permission" : "Codex does not need permission")
    }

    private var background: Color {
        needsPermission ? Color(nsColor: .systemOrange).opacity(0.18) : Color.white.opacity(0.08)
    }

    private var border: Color {
        needsPermission ? Color(nsColor: .systemOrange).opacity(0.35) : Color.white.opacity(0.12)
    }

    private var symbolColor: Color {
        needsPermission ? Color(nsColor: .systemOrange) : .white.opacity(0.45)
    }

    private var questionColor: Color {
        needsPermission ? .white.opacity(0.92) : .white.opacity(0.42)
    }
}
