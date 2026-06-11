# Luma

A Launchpad-style macOS launcher built with SwiftUI and AppKit.

## Project Structure

```text
Sources/MacOSLauncher/
  App/                  App entry, lifecycle, dependency composition, main menu
  Core/
    Models/             Shared data models and persisted state
    Errors/             Typed recoverable and service errors
    Utilities/          Pure, testable business utilities
  Services/
    ApplicationScanner/ Installed application discovery
    Cache/              Application scan cache
    HotKey/             Carbon global shortcut registration
    Launch/             Application launch and Finder reveal
    Logging/            Local diagnostic logging
    LoginItem/          Launch at Login
    Permissions/        Permission status and System Settings links
    Preferences/        User preference persistence
  Features/
    Launcher/           Launcher state and window control
    LauncherUI/         AppKit launcher views and interaction
    Settings/           Native settings window
```

## Features

- Full-screen translucent launcher window with animated show/hide.
- App scanning from `/Applications`, `/System/Applications`, `/System/Applications/Utilities`, and `~/Applications`.
- Search bar at the top.
- App folders with rename, delete, add, and remove support.
- Custom app ordering by drag and drop.
- A-Z sorting mode.
- Pagination with page dots and trackpad horizontal swipe.
- Custom per-page layout: choose rows and columns from the `Layout` menu.
- Native Dock app with a standard menu, settings window, and `Control-Option-Space` shortcut.
- Cached application index for immediate presentation with background refresh.
- Launch at Login, permission guidance, multi-display placement, and local recovery logs.
- Escape closes the launcher.
- Best-effort pinch gesture support: pinch in opens, spread out closes when macOS delivers magnify events to the app.

## Build

```sh
swift build
```

To create a `.app` bundle:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
```

The bundle is written to:

```text
.build/release/Luma.app
```

## Install

```sh
chmod +x scripts/*.sh
scripts/install-app.sh
```

This installs the app to `~/Applications/Luma.app` and opens it. Launch at Login can be enabled in Luma Settings.

## Notes

macOS does not expose a public API for replacing the system launcher or globally binding the exact system four-finger Launchpad gesture as the OS default. Luma uses a global shortcut and listens for magnification gestures when macOS delivers them.
