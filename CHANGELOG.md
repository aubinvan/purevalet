# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

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
