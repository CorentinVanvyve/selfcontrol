# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SelfControl is a macOS application (Objective-C) that blocks access to distracting websites by manipulating macOS's packet filter (PF) and `/etc/hosts`. Blocks are tamper-resistant: they survive reboots and app deletion until the timer expires.

## Building for Development

```bash
# Install dependencies (first time only)
sudo gem install cocoapods
pod install

# Open the workspace (NOT the .xcodeproj)
open selfcontrol.xcworkspace
```

Build and run from Xcode. You may need to update/remove code signing settings. The project targets macOS 10.10+.

## Running Tests

Tests live in `SelfControlTests/`. Run them via Xcode's test navigator or:

```bash
xcodebuild test -workspace selfcontrol.xcworkspace -scheme SelfControl -destination 'platform=macOS'
```

To run a single test class:

```bash
xcodebuild test -workspace selfcontrol.xcworkspace -scheme SelfControl -destination 'platform=macOS' -only-testing:SelfControlTests/SCUtilityTests
```

## Architecture

The app is split into multiple targets that communicate via XPC:

### Main App (`SelfControl` target)
- `AppController` — NSApplicationDelegate; entry point for the UI. Manages the main window, blocklist editor, and timer window.
- `TimerWindowController` / `DomainListWindowController` — secondary windows shown during an active block.
- `PreferencesGeneralViewController` / `PreferencesAdvancedViewController` — preferences panel (via MASPreferences pod).
- `SCDurationSlider` — custom slider for selecting block duration.
- `SCXPCClient` (`Common/`) — thin wrapper the app uses to talk to the daemon over XPC.

### Daemon (`org.eyebeam.selfcontrold` target, `Daemon/`)
- `SCDaemon` — singleton that runs the `selfcontrold` helper process; accepts XPC connections and runs periodic block-integrity checkups.
- `SCDaemonBlockMethods` — stateless class containing all block start/update/checkup logic called by XPC handlers.
- `SCDaemonXPC` — XPC listener that implements `SCDaemonProtocol` and delegates to `SCDaemonBlockMethods`.
- `SCDaemonProtocol` — the XPC interface shared between the app and daemon.

### Block Management (`Block Management/`)
- `BlockManager` — orchestrates both blocking mechanisms (PF + hosts file). Supports blocklist and allowlist modes.
- `PacketFilter` — writes and loads PF rules via `/sbin/pfctl`.
- `HostFileBlockerSet` / `HostFileBlocker` — manages `/etc/hosts` entries.
- `AllowlistScraper` — resolves linked domains (e.g. CDNs, tracking pixels) to block alongside a target domain.
- `SCBlockEntry` / `SCBlockFileReaderWriter` — model and persistence for individual blocklist entries.

### Common (`Common/`)
- `SCSettings` — singleton for reading/writing the app's settings file (stored at a secured path, not NSUserDefaults). Used by both the app and the daemon.
- `SCXPCClient` — the client-side XPC connection to the daemon.
- `SCFileWatcher` — watches the settings file for changes.
- `SCErr` / `SCSentry` — error handling and crash reporting (Sentry).
- `Utility/` — `SCBlockUtilities`, `SCMiscUtilities`, `SCMigrationUtilities`, `SCHelperToolUtilities` — stateless utility classes for block state detection, blocklist cleaning, legacy migration, and helper tool operations.

### SelfControl Killer (`SelfControl Killer` target)
A helper app that removes an expired block. Runs as a LaunchAgent.

### SCKillerHelper (`SCKillerHelper` target)
A privileged helper that does the actual removal of PF rules and hosts entries (requires root).

### CLI (`selfcontrol-cli` target, `cli-main.m`)
Command-line interface. Supports `start`, `remove`, `is-running`, `print-settings`, `version`. Uses `XPMArguments` (via `ArgumentParser/`) for argument parsing.

## Key Design Constraints

- **Tamper-resistance**: The block is stored in a secured settings file and enforced by the daemon, not the app. Quitting or deleting the app doesn't clear the block.
- **Privilege escalation**: The daemon runs as root via a LaunchDaemon (`org.eyebeam.SelfControl.plist`). The app communicates with it over XPC and passes `NSData`-serialized `AuthorizationRef` tokens for privileged operations.
- **Dual blocking mechanism**: Both PF (packet-level) and `/etc/hosts` (DNS-level) are used for robustness.
- **Allowlist mode**: Instead of blocking listed domains, the block can allow *only* listed domains and block everything else.

## Dependencies (via CocoaPods)

- `MASPreferences` — preferences window framework
- `TransformerKit` / `FormatterKit` — value transformers and time formatting
- `LetsMove` — prompts user to move app to `/Applications`
- `Sentry` — crash reporting (pinned to 7.3.0 from git)
