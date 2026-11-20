# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Redis: start / stop Homebrew Redis from the menu and the settings (`brew services run|stop redis`, never registered at login), included in *Start All* / *Stop All* and stopped when PureValet quits.
- E-mail capture with Mailpit: PureValet runs it bound to 127.0.0.1 (inbox on `http://127.0.0.1:8025`, SMTP on port 1025, messages kept between runs). In the no-admin mode PHP's `mail()` (WordPress's default) is routed there; the settings give the Laravel `.env` lines to copy.
- phpMyAdmin login is now `admin` / `admin`: PureValet creates this local-only MariaDB account (never changing an existing one) when installing or opening phpMyAdmin.
- Redis and Mailpit appear in the *About* versions. When they are missing, the settings show the `brew install` command (PureValet installs nothing).

### Fixed
- 502 Bad Gateway after Homebrew replaced a PHP version (e.g. `brew upgrade` turning `php` 8.5 into 8.6): in the no-admin mode, the global PHP and isolated sites now fall back to the closest installed version (the next newer one if possible) and `valet.sock` is repaired; with an administrator account, *Start* / *Restart* run `valet use` on that version first. A warning in the menu and the settings names the version replaced.

## [0.9.3] - 2026-11-20

### Changed
- No-admin mode only *requires* what it really needs: the `.test` DNS pointing at PureValet and Valet's certificate authority trusted. Valet's former root services are reported as harmless information (they are no longer used) instead of blocking with a "Finish setup" prompt, so nobody is pushed to use an administrator account for them.

## [0.9.2] - 2026-11-20

### Fixed
- One-time no-admin setup: the macOS dialog now says to replace the pre-filled (standard) name with an administrator account, the settings list this Mac's administrator accounts, and a refused password or a cancel is explained instead of "failed (exit code 1)".
- The leftover root PHP-FPM pattern is regex-escaped, so `pkill` really stops it.

## [0.9.1] - 2026-11-20

### Fixed
- The one-time no-admin setup now also removes Valet's root services named `sh.brew.*` (Homebrew 5+), not only `homebrew.mxcl.*`. A root dnsmasq was restarted at every boot and kept the "Finish setup" message visible.

## [0.9.0] - 2026-11-20

### Added
- **No-admin mode for standard macOS accounts.** When the user is not an administrator, PureValet runs nginx, PHP-FPM and dnsmasq itself, under the user's account, with configs generated from Valet's own files and stubs: no `sudo`, no password, ever. nginx listens on all interfaces (the only way without root) and only accepts connections from the Mac itself; dnsmasq answers on `127.0.0.1:1053`. The services are PureValet's child processes, so quitting stops them.
- One-time setup for that mode, through the standard macOS administrator dialog: points `/etc/resolver/<tld>` to the rootless DNS, removes Valet's root services and leftover root processes, trusts Valet's certificate authority.
- In that mode, link, unlink, park, forget, secure (certificate signed by Valet's CA), isolate, global PHP and proxies are done directly on Valet's files.

### Changed
- Sites, parked folders and proxies are read from Valet's files instead of `valet links/parked/proxies`, which run `sudo` internally: lists no longer disappear when `sudo` is unavailable.

## [0.8.0] - 2026-11-20

### Added
- **Dark and tinted app icon**: on macOS 26+, the icon follows the system icon appearance (graphite tile in dark mode, tinted mode supported), built from an Icon Composer file (`Resources/AppIcon.icon`). macOS 14–15 keep the light icon.
- The README logo follows GitHub's light/dark theme.
- Contribution guidelines, code of conduct, security policy, support guide, issue and pull request templates, CODEOWNERS, EditorConfig.
- Release workflow: pushing a `vX.Y.Z` tag builds the DMG on GitHub and publishes the release with its changelog section.
- Dependabot keeps the CI actions up to date.

### Changed
- CI builds with warnings as errors, checks shell scripts, and cancels outdated runs.
- `scripts/update-cask.sh` uses the published SHA-256 of the release instead of a local build.

## [0.7.1] - 2026-11-20

### Added
- Opening PureValet again (Spotlight, Launchpad, Finder) while it runs shows the settings window, a way in when the menu bar icon is hidden behind the notch of a crowded menu bar.
- The settings window opens by itself on first launch.
- `PureValet --install-phpmyadmin` runs the built-in phpMyAdmin installer headlessly (testing, scripts).

### Fixed
- The settings window is forced to the front when opened from the menu bar.

## [0.7.0] - 2026-11-20

### Added
- **Built-in phpMyAdmin**: *Settings → General → Database → phpMyAdmin → Install…* (or *Install phpMyAdmin…* in the menu). PureValet downloads the latest official release, checks its SHA-256, installs it in `~/Library/Application Support/PureValet/phpMyAdmin`, writes a config for the local MariaDB socket and serves it on `https://phpmyadmin.test`. It runs on a PHP version phpMyAdmin supports (isolated automatically, e.g. PHP 8.3 when the global PHP is 8.5). Login: macOS user name and an empty password (MariaDB `unix_socket`), so no password is stored. *Update to x.y.z* when a newer release exists.
- *Open phpMyAdmin* in the menu.

## [0.6.0] - 2026-11-20

### Added
- Status dots in the menu bar menu: green when Valet runs, red when it is stopped, and one dot per site (green when it answers, red on a server error or no answer). Sites are checked with one HEAD request each, in parallel, when the menu opens.
- The same dots in *Settings → Sites*.
- When `valet trust` is not set up, PureValet offers once to enable it (one last password) instead of asking for the password on every action.

### Fixed
- A refresh requested while another one was running returned immediately, which could show empty or stale lists right after launch or after an action.
- App Transport Security exception for `.test` and local addresses, needed for the site checks over plain HTTP.

## [0.5.3] - 2026-11-20

### Fixed
- Valet's internal `~/.config/valet/Sites` folder no longer appears in *Parked folders*: forgetting it by mistake would have broken every linked site.
- A failed `valet` command during a refresh keeps the last known sites, proxies and parked folders instead of showing empty lists.

## [0.5.2] - 2026-11-20

### Fixed
- PureValet now calls Valet through Homebrew's `bin/valet` symlink (created by `valet install`). `valet trust` only whitelists that path, so calling the Composer path still asked for a password after `valet trust`.

## [0.5.1] - 2026-11-20

### Fixed
- Valet showed as "stopped" while running when `valet trust` was not set up: since Valet 4.13, `valet status` needs `sudo`. PureValet now also checks that nginx, PHP-FPM (`valet` pool) and dnsmasq are running.

## [0.5.0] - 2026-11-20

### Added
- Update check: one request to the GitHub Releases API, at most once a day (at launch or when the menu opens), plus *Check Now*. A *Download PureValet x.y.z…* menu item appears when a newer version exists. Can be turned off. No dependency, nothing installed automatically.
- Homebrew cask: `brew install --cask aubinvan/tap/purevalet`, then `brew upgrade --cask purevalet`.
- `scripts/update-cask.sh` publishes the cask for each release.

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
