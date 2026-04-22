import AppKit
import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var monitor: RateLimitMonitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let snapshot = monitor.snapshot {
                LimitCardView(title: "Short Window", subtitle: snapshot.primary.windowTitle, window: snapshot.primary)

                if let secondary = snapshot.secondary {
                    LimitCardView(title: "Long Window", subtitle: secondary.windowTitle, window: secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(snapshot.planType.capitalized, systemImage: "person.crop.circle.badge.checkmark")
                    Label("Updated \(snapshot.freshnessDescription)", systemImage: "clock.arrow.circlepath")
                    Label(snapshot.sourceFile.lastPathComponent, systemImage: "doc.text")
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No Codex Usage Data Yet",
                    systemImage: "gauge.badge.plus",
                    description: Text(monitor.errorMessage ?? "Start a Codex session and the menu bar meter will pick up the latest local rate-limit snapshot.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                Button("Refresh Now") {
                    monitor.refresh()
                }
                .keyboardShortcut("r")

                Button("Open Sessions Folder") {
                    NSWorkspace.shared.open(AppPreferences.sessionsDirectoryURL)
                }

                Spacer()

                Button("Settings") {
                    openSettings()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Usage Meter")
                    .font(.title3.weight(.semibold))

                Text("Remaining Codex rate limits from your local session logs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if monitor.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct LimitCardView: View {
    let title: String
    let subtitle: String
    let window: CodexRateLimitSnapshot.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(window.remainingPercentString)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: window.remainingProgressValue)
                .tint(progressTint)

            HStack {
                Label("Used \(window.usedPercentString)", systemImage: "chart.bar.fill")
                Spacer()
                Label(resetText, systemImage: "timer")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var progressTint: Color {
        switch window.remainingPercent {
        case 80...:
            return .green
        case 50..<80:
            return .orange
        default:
            return .red
        }
    }

    private var resetText: String {
        let relative = CodexRateLimitSnapshot.relativeDescription(for: window.resetsAt)
        return "Resets \(relative)"
    }
}
