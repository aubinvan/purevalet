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
"build/Valet Desktop.app/Contents/MacOS/ValetDesktop" --snapshot /tmp/valet.png
```

(AppKit-backed controls such as buttons render as placeholders in the snapshot; this is an `ImageRenderer` limitation.)

## Code layout

| File | Role |
| --- | --- |
| `Sources/ValetDesktop/App.swift` | Entry point, `MenuBarExtra`, `--snapshot` mode |
| `Sources/ValetDesktop/Shell.swift` | Runs commands with an explicit `PATH` and the `sudo` askpass helper |
| `Sources/ValetDesktop/ValetModel.swift` | Detection, parsing of Valet's tables, actions |
| `Sources/ValetDesktop/ContentView.swift` | UI |
| `scripts/make-icon.swift` | Regenerates `Resources/AppIcon.icns` |
| `scripts/make-dmg.sh` | Builds the DMG and its SHA-256 |

## Releasing

1. Bump `VERSION` and add a section to `CHANGELOG.md`.
2. `./scripts/make-dmg.sh`
3. Commit, tag `vX.Y.Z`, push, then:

```bash
gh release create vX.Y.Z build/ValetDesktop-X.Y.Z.dmg build/ValetDesktop-X.Y.Z.dmg.sha256 --notes-file <notes>
```

## Localization

The UI is currently in French. English strings / a String Catalog are a welcome contribution.
