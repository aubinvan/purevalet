# Contributing

Issues and pull requests are welcome.

## Principles

- **Stay light.** No background timers, no daemons, no helper process left running after quit. State is read when the menu opens and after each action.
- **Never install or reconfigure anything on the user's behalf.** The app only runs `valet` and `brew services` commands the user explicitly clicks.
- **No dependencies.** Plain SwiftUI + Foundation, Swift Package Manager only.

## Development

```bash
swift build          # debug build
swift test           # unit tests (Valet table parsing, slug)
./build.sh           # release .app in build/
./scripts/make-dmg.sh  # DMG in build/
```

Quick visual check without clicking the menu bar:

```bash
"build/PureValet.app/Contents/MacOS/PureValet" --snapshot /tmp/valet-snap
```

This writes one PNG per settings tab (`general.png`, `sites.png`, `proxies.png`, `about.png`). The menu bar menu itself cannot be captured this way.

## Code layout

| File | Role |
| --- | --- |
| `Sources/PureValet/App.swift` | Entry point, `MenuBarExtra` (menu style), `--snapshot` mode |
| `Sources/PureValet/MenuContent.swift` | Native menu bar menu |
| `Sources/PureValet/SettingsWindow.swift` | Settings window: sidebar + General / Sites / Proxies / About panes |
| `Sources/PureValet/Shell.swift` | Runs commands with an explicit `PATH` and the `sudo` askpass helper |
| `Sources/PureValet/ValetModel.swift` | Detection, parsing of Valet's tables, actions |
| `scripts/make-icon.swift` | Builds `AppIcon.icns`, the menu bar template icon and `docs/icon.png` from `Resources/source/logo.png` |
| `scripts/make-dmg.sh` | Builds the DMG and its SHA-256 |

## Releasing

1. Bump `VERSION` and add a section to `CHANGELOG.md`.
2. `./scripts/make-dmg.sh`
3. Commit, tag `vX.Y.Z`, push, then:

```bash
gh release create vX.Y.Z build/PureValet-X.Y.Z.dmg build/PureValet-X.Y.Z.dmg.sha256 --notes-file <notes>
```

## Localization

The UI is currently in French. English strings / a String Catalog are a welcome contribution.
