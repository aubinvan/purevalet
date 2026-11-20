<p align="center">
  <img src="docs/icon.png" width="128" alt="PureValet icon">
</p>

<h1 align="center">PureValet</h1>

<p align="center">
  A tiny native macOS menu bar app that runs your whole <a href="https://laravel.com/docs/valet">Laravel Valet</a> environment, no terminal needed.<br>
  <a href="README.fr.md">Version française</a>
</p>

<p align="center">
  <a href="https://github.com/aubinvan/purevalet/releases/latest"><img src="https://img.shields.io/github/v/release/aubinvan/purevalet" alt="Latest release"></a>
  <a href="https://github.com/aubinvan/purevalet/actions/workflows/ci.yml"><img src="https://github.com/aubinvan/purevalet/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

---

<p align="center">
  <img src="docs/screenshot-general.png" width="640" alt="PureValet settings window">
</p>

Valet is the lightest local PHP environment on macOS (nginx + PHP-FPM + dnsmasq, no Docker, no VM), but it is CLI-only and its services keep running until you stop them. PureValet turns it into an app you open when you work and quit when you are done:

- **Open PureValet → your stack runs.** Start Valet (nginx, PHP-FPM, dnsmasq) and Homebrew MariaDB from the menu, or automatically at launch.
- **Quit PureValet → everything stops.** Valet and MariaDB are stopped and unregistered from launchd: nothing keeps running in the background and nothing restarts at boot.
- **Native and light.** SwiftUI, DMG under 1 MB, universal (Apple Silicon + Intel), no dependencies, no timers, no daemon.
- **Installs nothing.** If Valet is missing, PureValet says so and shows the command to run yourself.
- **English and French.** The app follows your macOS language.

> PureValet is a community project and is not affiliated with or endorsed by Laravel.

## Interface

Inspired by [Hex](https://hex.audio): a plain native menu for everyday actions, and a settings window for the rest.

- **Menu bar menu**: status, *Start All Services* / *Stop All Services*, Start / Restart / Stop Valet, *Sites* (open, link or park a folder), *Proxies*, *Global PHP* (checkmark on the active version), *Logs & Files*, MariaDB, **Settings… ⌘,**, **Quit ⌘Q**.
- **Settings window** with a sidebar:
  - *General*: status, Valet CLI version, domain, logs and configuration folders, global PHP, password-free commands, MariaDB, app behaviour (start at launch, stop at quit, open at login).
  - *Sites*: linked and parked sites, HTTPS, per-site PHP, copy URL, Finder, Terminal, unlink; parked folders (park / forget).
  - *Proxies*: list, add, remove.
  - *About*: versions of PureValet, Valet, PHP, nginx, dnsmasq, Composer and MariaDB; update check.

The menu bar logo is dimmed while Valet is stopped. In the menu, a **green dot** means Valet runs and a **red dot** means it is stopped; each site also gets a dot (green: it answers, red: server error or no answer).

If `valet trust` is not set up, PureValet offers once to enable it instead of asking for your password on every action.

## Features

| Area | What you can do | Command used |
| --- | --- | --- |
| Services | Start / stop everything at once, at launch or at quit | `valet start\|stop`, `brew services run\|stop mariadb` |
| Valet | Start, restart, stop, see the CLI version | `valet start\|restart\|stop`, `valet --version` |
| Sites | Linked and parked sites: open, copy URL, Finder, Terminal | `valet links`, `valet parked` |
| Link / Park | Link one folder, or park a folder of projects; forget it | `valet link`, `valet park`, `valet forget` |
| HTTPS | Secure / unsecure a site | `valet secure`, `valet unsecure` |
| PHP | Global version, or a version per site | `valet use`, `valet isolate`, `valet unisolate` |
| Proxies | Proxy `name.test` to a local port (Node, Vite…) | `valet proxy`, `valet unproxy` |
| Password | Stop the password prompts | `valet trust` |
| Files | Open Valet logs and configuration | `~/.config/valet` |
| MariaDB | Start / stop Homebrew MariaDB (not registered at login) | `brew services run\|stop mariadb` |

PureValet also warns you if Yerd is installed, since it competes for ports 80/443, the `.test` DNS and port 3306.

## Requirements

- macOS 14 Sonoma or later
- [Homebrew](https://brew.sh) (`/opt/homebrew` or `/usr/local`)
- Laravel Valet, installed with Composer:

```bash
composer global require laravel/valet
```

```bash
valet install
```

## Install

### With Homebrew (recommended)

```bash
brew install --cask aubinvan/tap/purevalet
```

Update later with `brew upgrade --cask purevalet`.

### Manually

1. Download `PureValet-x.y.z.dmg` from the [latest release](https://github.com/aubinvan/purevalet/releases/latest).
2. Open it and drag **PureValet** to **Applications**.
3. First launch (both methods): the app is ad-hoc signed but **not notarized** (no paid Apple Developer account), so macOS blocks it once. Either open it and go to **System Settings → Privacy & Security → Open Anyway**, or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/PureValet.app"
```

Check the download against the `.sha256` file attached to the release:

```bash
shasum -a 256 -c PureValet-x.y.z.dmg.sha256
```

## Updates

PureValet checks GitHub for a new release **at most once a day** (one request, when it starts or when you open the menu). When one is available, a *Download PureValet x.y.z…* item appears in the menu, and the About tab shows the release notes and a download button. Nothing is downloaded or installed without you.

- Turn it off in **Settings → About → Check for updates automatically**, or click **Check Now**.
- Homebrew users: `brew upgrade --cask purevalet`.

## Starting and stopping

In **Settings → General → App**:

| Option | Default | Effect |
| --- | --- | --- |
| Start services when PureValet opens | Off | Starts Valet and MariaDB at launch |
| Stop all services when quitting | **On** | Stops Valet and MariaDB when you quit PureValet (or log out / shut down) |
| Open at login | Off | Opens PureValet when you log in |

Why it matters: `valet start` registers nginx, PHP-FPM and dnsmasq with launchd, so without PureValet they would keep running and restart at every boot. Quitting PureValet stops and unregisters them. MariaDB is started with `brew services run`, which never registers it at login.

## Administrator password (`sudo`)

Valet re-runs some commands with `sudo` (start, stop, use, secure, isolate…). The app has no terminal, so it gives `sudo` an *askpass* helper: a standard macOS dialog asks for your password, which goes straight to `sudo` (PureValet never reads or stores it).

To avoid the prompt (recommended if you use *Stop all services when quitting*), click **Settings → General → Password-free commands → Enable…**, which runs `valet trust` once.

## Build from source

Requires Xcode 15.4+ or the Command Line Tools (Swift 5.10+).

```bash
git clone https://github.com/aubinvan/purevalet.git && cd purevalet
```

```bash
./build.sh
```

```bash
open build/PureValet.app
```

Build the DMG (output in `build/`, with its SHA-256):

```bash
./scripts/make-dmg.sh
```

Run the tests and the translation check:

```bash
swift test
```

```bash
python3 scripts/check-l10n.py
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code layout, translations and the release process.

## How it works

- Commands are launched directly (no shell) with an explicit `PATH`, because apps started from Finder do not inherit your shell `PATH`. Homebrew analytics and auto-update are disabled for those commands.
- Valet's tables (`valet links`, `valet parked`, `valet proxies`) are parsed by column name; `valet paths` is read as JSON.
- Installed PHP versions and component versions are read from Homebrew's `opt/` symlinks, without calling `brew`.
- State is read when the menu or the settings window opens, and after each action. No timer.

## Limitations

- Not notarized (see Install).
- Tested on Apple Silicon; the Intel build is untested.
- `valet share` and Expose are not supported.

## License

[MIT](LICENSE): use, copy, modify, sell, redistribute, anything. Just keep the copyright notice.
