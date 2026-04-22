<img width="464" height="570" alt="Screenshot " src="https://github.com/user-attachments/assets/4f36ffa9-1d20-40fa-96de-be05a96708fa" />
# Codex Usage Meter

Codex Usage Meter is a native macOS menu bar app that keeps your remaining Codex rate limits visible at all times.

It reads the same local `rate_limits` snapshots Codex writes into `~/.codex/sessions`, so it does not need your ChatGPT password, does not scrape the web app, and does not upload chat contents anywhere.

## What It Shows

- Remaining percentage in the short and long Codex windows directly in the menu bar
- Reset timing for both windows in a native popup
- The plan type reported by Codex
- The session log location used as the data source
- A true menu-bar-only app experience with no Dock icon

## Privacy Model

- No login screen
- No password capture
- No browser automation
- No network requests
- Reads only the newest tail section of recent `rollout-*.jsonl` files
- Hides local filesystem paths from the menu UI to avoid leaking usernames in screenshots

That last point matters: the app does not ingest your full history to compute the meter. It looks for the latest `rate_limits` payload near the end of recent Codex session files and stops there.

## Build

1. Generate the Xcode project:

   ```bash
   xcodegen generate
   ```

2. Open `CodexUsageMeter.xcodeproj` in Xcode.

3. Run the `CodexUsageMeter` scheme.

You can also build from the command line:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project CodexUsageMeter.xcodeproj \
  -scheme CodexUsageMeter \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

To generate distributable files:

```bash
zsh Scripts/package_app.sh
```

That creates both a `.zip` and a drag-to-Applications `.dmg` in `dist/`.

By default, the packaging script applies an ad-hoc bundle signature so the app is packaged as a proper macOS bundle instead of an invalid unsigned artifact.

If you have a Developer ID Application certificate installed, you can build a stronger public release by setting `CODE_SIGN_IDENTITY` before packaging:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" zsh Scripts/package_app.sh
```

To regenerate the percent-sign app icon:

```bash
swift Scripts/generate_app_icon.swift CodexUsageMeter/Resources/Assets.xcassets/AppIcon.appiconset
```

## GitHub Release Notes

This repo is ready for GitHub distribution as a direct-download macOS utility. Before your first public release, you will likely want to:

- sign with Developer ID and notarize the release build if you want the smoothest install experience on other Macs

## Compatibility

- macOS 14+
- Requires local Codex session files under `~/.codex/sessions` or a custom folder you set in Settings
