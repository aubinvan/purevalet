# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.4.0] - 2026-11-20

### Added
- **PureValet drives the whole environment**: *Start All Services* / *Stop All Services*, optional start at launch, and **stop everything when quitting** (on by default). `valet stop` unregisters nginx, PHP-FPM and dnsmasq from launchd, so nothing keeps running or restarts at boot.
- MariaDB is started with `brew services run` (never registered at login).
- Valet CLI version, and versions of PHP, nginx, dnsmasq, Composer and MariaDB (About).
- Restart Valet.
- Parked folders: list, park, forget; parked sites appear in the site list.
- Site actions: copy URL, open in Terminal.
- Open the Valet logs and configuration folders.
- Password-free commands (`valet trust`) from the settings.
- Open at login (`SMAppService`).
- `scripts/check-l10n.py` (also run in CI) checks that every UI string is translated.

### Changed
- **English is now the default language**, with a full French translation; the app follows the macOS language.
- Homebrew analytics and auto-update are disabled for the commands PureValet runs.

## [0.3.0] - 2026-11-20

### Changed
- The app is renamed **PureValet** (formerly Valet Desktop): app bundle `PureValet.app`, bundle identifier `dev.aubin.purevalet`, DMG `PureValet-x.y.z.dmg`, repository `aubinvan/purevalet`.

## [0.2.1] - 2026-11-20

### Changed
- New logo: app icon, menu bar icon (template image, dimmed when Valet is not running) and README icon.
- About pane shows the app icon.
- `scripts/make-icon.swift` now builds every icon from `Resources/source/logo.png`.

## [0.2.0] - 2026-11-20

### Changed
- New Hex-inspired interface: a native macOS menu in the menu bar (status, Start / Stop, Sites, Proxies and global PHP submenus, MariaDB, Settings… ⌘, and Quit ⌘Q).
- Full settings window with a sidebar (General, Sites, Proxies, About) and grouped forms, created on demand and released when closed.
- State refreshes when the menu opens (no timer).

### Added
- "Copy" button for the Valet install commands, About pane with version and environment info.
- `--snapshot <dir>` now captures the real settings window, one PNG per tab.

## [0.1.0] - 2026-11-20

### Added
- Menu bar app (SwiftUI, macOS 14+, universal arm64 + x86_64).
- Valet status (running / stopped / not installed) with Start / Stop.
- Linked sites list (`valet links`): open in browser, secure / unsecure, per-site PHP (`isolate` / `unisolate`), unlink, reveal in Finder.
- "Link a folder…" (`valet link`).
- Global PHP version switch (`valet use`), based on installed Homebrew PHP formulae.
- Node / Vite proxies (`valet proxy` / `valet unproxy`).
- Optional Homebrew MariaDB start / stop.
- Native macOS password prompt for commands that need `sudo` (askpass).
- Detection of Yerd (port 80/443 and `.test` DNS conflict warning).
- DMG packaging script and CI workflow.
