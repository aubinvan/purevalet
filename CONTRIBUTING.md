# Contributing to PureValet

Thanks for wanting to help! Bug reports, ideas, translations, documentation and code are all welcome. English and French are both fine in issues and pull requests.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go through [SECURITY.md](SECURITY.md), never a public issue. Questions go to [Discussions](https://github.com/aubinvan/purevalet/discussions).

## Ways to contribute

| You want to… | Do this |
| --- | --- |
| Report a bug | [Open an issue](https://github.com/aubinvan/purevalet/issues/new/choose) with the bug template |
| Suggest a feature | Start a [Discussion](https://github.com/aubinvan/purevalet/discussions) or use the feature template |
| Fix a translation / add a language | See [Localization](#localization) |
| Write code | Pick an issue labelled `good first issue` or `help wanted`, comment that you are on it, then follow [the workflow](#workflow) |

For anything bigger than a small fix, **open an issue or a discussion first**, so we agree on the approach before you spend time on it.

## Principles

Every change must keep these true:

- **Stay light.** No background timers, no daemons, no helper process left running after quit. State is read when the menu opens and after each action.
- **Leave nothing behind.** By default, quitting PureValet stops Valet and MariaDB (`AppDelegate` in `App.swift`).
- **Never install or reconfigure anything without the user.** The app only runs commands the user explicitly asks for.
- **No dependencies.** SwiftUI, AppKit and Foundation only, Swift Package Manager, no third-party packages.
- **Never handle secrets.** Passwords go from the macOS dialog straight to `sudo`; nothing is stored.

## Development setup

Requirements: macOS 14+, Xcode 15.4+ or the Command Line Tools (Swift 5.10+), Python 3 (for the translation check). Laravel Valet is only needed to try the actions for real.

```bash
git clone https://github.com/<you>/purevalet.git && cd purevalet
```

```bash
swift build && swift test
```

```bash
./build.sh && open build/PureValet.app
```

Other useful commands:

| Command | What it does |
| --- | --- |
| `swift build -Xswiftc -warnings-as-errors` | Build like CI (warnings fail) |
| `python3 scripts/check-l10n.py` | Check that every UI string is translated |
| `./scripts/make-dmg.sh` | Build the app and the DMG in `build/` |
| `build/PureValet.app/Contents/MacOS/PureValet --snapshot /tmp/snap` | Render the settings window, one PNG per tab (the menu bar menu cannot be captured this way) |
| `build/PureValet.app/Contents/MacOS/PureValet -AppleLanguages '(fr)'` | Run in another language |
| `build/PureValet.app/Contents/MacOS/PureValet --install-phpmyadmin` | Run the phpMyAdmin installer without the UI |

Quit any installed PureValet before running your build: both share the bundle identifier.

## Workflow

1. **Fork** the repository and create a branch from `main`: `fix/short-description`, `feat/short-description` or `docs/…`.
2. Make **small, focused commits**. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `fix: keep sites list when valet links fails`, `feat: add Redis start/stop`, `docs: …`, `ci: …`, `i18n: …`.
3. Add or update **tests** in `Tests/PureValetTests` for any parsing or logic change (pure functions are `nonisolated static` so they are easy to test).
4. Add an entry under **`## [Unreleased]`** in [CHANGELOG.md](CHANGELOG.md).
5. Run the checks: `swift build -Xswiftc -warnings-as-errors`, `swift test`, `python3 scripts/check-l10n.py`.
6. Open a **pull request** and fill in the template. CI must be green and the maintainer must approve before merging. PRs are **squash-merged**, so the PR title becomes the commit message: write it as a Conventional Commit.

### Code style

- Follow the existing style: 4 spaces, Swift API Design Guidelines, explicit types where they help reading.
- Keep UI strings in English in the code; translations go in `Resources/<lang>.lproj`.
- Comments explain *why*, not *what*. Public behaviour that is not obvious gets a doc comment (`///`).
- Run external commands through `Shell.run` only (no shell, explicit `PATH`).

## Code layout

| File | Role |
| --- | --- |
| `Sources/PureValet/App.swift` | Entry point, `MenuBarExtra`, `AppDelegate` (start at launch, stop at quit, reopen), `--snapshot` / `--install-phpmyadmin` modes |
| `Sources/PureValet/MenuContent.swift` | Native menu bar menu |
| `Sources/PureValet/SettingsWindow.swift` | Settings window: sidebar + General / Sites / Proxies / About |
| `Sources/PureValet/ValetModel.swift` | State, detection, parsing of Valet's output, actions |
| `Sources/PureValet/Shell.swift` | Runs commands with an explicit `PATH` and the `sudo` askpass helper |
| `Sources/PureValet/PhpMyAdmin.swift` | Built-in phpMyAdmin: release feed, download + SHA-256, config |
| `Sources/PureValet/Updater.swift` | Daily GitHub release check |
| `Sources/PureValet/StatusDot.swift` | Green/red/grey dots for the menu |
| `Tests/PureValetTests/` | Unit tests |
| `Resources/` | Icons and translations |
| `scripts/` | Icon (`make-icon.swift`: .icns, menu bar, docs; `make-icon-composer.swift`: `Resources/AppIcon.icon` with light/dark/tinted), DMG, cask, changelog and translation tooling |
| `.github/` | CI, release workflow, issue/PR templates, Dependabot |

## Localization

English is the development language: UI strings are written in English in the code (`Text("…")`, `Button("…")`, `String(localized: "…")`) and the English text is the key. Translations live in `Resources/<lang>.lproj/Localizable.strings` (currently `fr`).

After adding or changing a string, update the French file and run `python3 scripts/check-l10n.py`: it lists missing and unused keys, and CI fails on missing keys. Use `Text(verbatim:)` for text that must not be translated.

To add a language, create `Resources/<lang>.lproj/Localizable.strings` and add the code to the `for lang in …` loop in `build.sh` and to `CFBundleLocalizations`.

## Releasing (maintainers)

1. Move the `## [Unreleased]` entries of `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading and set `VERSION` to `X.Y.Z`.
2. Commit (`chore: release X.Y.Z`), tag and push:

```bash
git tag -a vX.Y.Z -m "PureValet X.Y.Z" && git push origin main vX.Y.Z
```

3. The **Release** workflow builds the DMG on GitHub, checks the tag matches `VERSION`, and publishes the release with the changelog section as notes.
4. Update the Homebrew cask (it verifies the published DMG against its published SHA-256):

```bash
./scripts/update-cask.sh
```

Running apps pick up the new version through their daily update check.
