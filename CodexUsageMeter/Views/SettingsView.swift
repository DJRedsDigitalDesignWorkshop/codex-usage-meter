import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: RateLimitMonitor

    @AppStorage(AppPreferences.sessionsDirectoryKey)
    private var sessionsDirectoryPath = AppPreferences.defaultSessionsDirectoryURL.path

    @AppStorage(AppPreferences.refreshIntervalKey)
    private var refreshInterval = 15.0

    @State private var sourceError: String?

    private let refreshChoices: [Double] = [5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section("Source") {
                LabeledContent("Selected folder", value: selectedFolderLabel)

                Text("The app reads only the newest tail section of recent `rollout-*.jsonl` files to recover the latest `rate_limits` snapshot. It does not send your prompts or chat contents anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Default location: `~/.codex/sessions`")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Choose a different folder only if your Codex session logs live outside the default location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Choose Folder…") {
                        chooseFolder()
                    }

                    Button("Use Default") {
                        UserDefaults.standard.set(AppPreferences.defaultSessionsDirectoryURL.path, forKey: AppPreferences.sessionsDirectoryKey)
                        sessionsDirectoryPath = AppPreferences.defaultSessionsDirectoryURL.path
                        sourceError = nil
                        monitor.reloadTimer()
                        monitor.refresh()
                    }
                }

                if let sourceError {
                    Text(sourceError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Refresh") {
                Picker("Refresh interval", selection: $refreshInterval) {
                    ForEach(refreshChoices, id: \.self) { seconds in
                        Text("\(Int(seconds)) seconds").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: refreshInterval) { _, _ in
                    applyRefreshChanges()
                }
            }

            Section("Status") {
                if let snapshot = monitor.snapshot {
                    LabeledContent("Menu bar text", value: "\(snapshot.primary.remainingPercentString) \(snapshot.secondary?.remainingPercentString ?? "--%")")
                    LabeledContent("Plan", value: snapshot.planType.capitalized)
                    LabeledContent("Last update", value: snapshot.freshnessDescription)
                } else {
                    Text(monitor.errorMessage ?? "No snapshot loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var selectedFolderLabel: String {
        if sessionsDirectoryPath == AppPreferences.defaultSessionsDirectoryURL.path {
            return "~/.codex/sessions"
        }

        return URL(fileURLWithPath: sessionsDirectoryPath, isDirectory: true).lastPathComponent
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex sessions folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = AppPreferences.defaultSessionsDirectoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return }

        UserDefaults.standard.set(url.path, forKey: AppPreferences.sessionsDirectoryKey)
        sessionsDirectoryPath = url.path
        sourceError = nil

        monitor.reloadTimer()
        monitor.refresh()
    }

    private func applyRefreshChanges() {
        monitor.reloadTimer()
        monitor.refresh()
    }
}
