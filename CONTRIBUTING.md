# Contributing

Issues and pull requests are welcome.

## Principles

- **Stay light.** No background timers, no daemons, no helper process left running after quit. State is read when the menu opens and after each action.
- **Leave nothing behind.** By default, quitting PureValet stops Valet and MariaDB (see `AppDelegate` in `App.swift`).
- **Never install or reconfigure anything on the user's behalf.** The app only runs `valet` and `brew services` commands the user explicitly clicks.
- **No dependencies.** Plain SwiftUI + Foundation, Swift Package Manager only.

## Development

```bash
swift build          # debug build
swift test           # unit tests (Valet output parsing, versions, slug)
./build.sh           # release .app in build/
./scripts/make-dmg.sh  # DMG in build/
```

Quick visual check without clicking the menu bar:

```bash
"build/PureValet.app/Contents/MacOS/PureValet" --snapshot /tmp/valet-snap
```

`--install-phpmyadmin` runs the built-in phpMyAdmin installer without the UI and prints the result.

This writes one PNG per settings tab (`general.png`, `sites.png`, `proxies.png`, `about.png`). The menu bar menu itself cannot be captured this way.

## Code layout

| File | Role |
| --- | --- |
| `Sources/PureValet/App.swift` | Entry point, `MenuBarExtra` (menu style), `AppDelegate` (start at launch, stop at quit), `--snapshot` mode |
| `Sources/PureValet/MenuContent.swift` | Native menu bar menu |
| `Sources/PureValet/PhpMyAdmin.swift` | Built-in phpMyAdmin: release feed, download + SHA-256, config |
| `Sources/PureValet/StatusDot.swift` | Green/red/grey dots for the menu |
| `Sources/PureValet/Updater.swift` | Daily GitHub release check (no dependency) |
| `Sources/PureValet/SettingsWindow.swift` | Settings window: sidebar + General / Sites / Proxies / About panes |
| `Sources/PureValet/Shell.swift` | Runs commands with an explicit `PATH` and the `sudo` askpass helper |
| `Sources/PureValet/ValetModel.swift` | Detection, parsing of Valet's tables, actions |
| `scripts/make-icon.swift` | Builds `AppIcon.icns`, the menu bar template icon and `docs/icon.png` from `Resources/source/logo.png` |
| `scripts/make-dmg.sh` | Builds the DMG and its SHA-256 |
| `scripts/update-cask.sh` | Publishes the Homebrew cask for the current version |
| `scripts/check-l10n.py` | Checks that every UI string has a French translation |
| `Resources/*.lproj/Localizable.strings` | Translations (English keys) |

## Releasing

1. Bump `VERSION` and add a section to `CHANGELOG.md`.
2. `./scripts/make-dmg.sh`
3. Commit, tag `vX.Y.Z`, push, then:

```bash
gh release create vX.Y.Z build/PureValet-X.Y.Z.dmg build/PureValet-X.Y.Z.dmg.sha256 --notes-file <notes>
```

4. Update the Homebrew cask in [aubinvan/homebrew-tap](https://github.com/aubinvan/homebrew-tap) (checks the published DMG against the local SHA-256 first):

```bash
./scripts/update-cask.sh
```

Running apps pick up the new version through their daily update check.

## Localization

English is the development language: UI strings are written in English directly in the code
(`Text("…")`, `Button("…")`, `String(localized: "…")`), and the English text is the key.
Translations live in `Resources/<lang>.lproj/Localizable.strings` (currently `fr`).

After adding or changing a string, update the French file and run:

```bash
python3 scripts/check-l10n.py
```

It lists missing and unused keys (CI fails on missing keys). Use `Text(verbatim:)` for text that must not be translated.
To add a language, create `Resources/<lang>.lproj/Localizable.strings` and add the code to the `for lang in …` loop in `build.sh` and to `CFBundleLocalizations`.

To try the app in another language without changing macOS:

```bash
build/PureValet.app/Contents/MacOS/PureValet -AppleLanguages '(fr)'
```
