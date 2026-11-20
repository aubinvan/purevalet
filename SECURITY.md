# Security Policy

## Supported versions

Only the **latest release** of PureValet receives security fixes. The app checks for updates daily, and `brew upgrade --cask purevalet` updates Homebrew installs.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report it privately through GitHub: **Security → Report a vulnerability** on [the repository](https://github.com/aubinvan/purevalet/security/advisories/new). You will get an answer as soon as possible (best effort, this is a community project), and a fix will be released before details are made public. You will be credited unless you prefer not to be.

## Scope

Areas that matter most, given what PureValet does on a developer's Mac:

- how commands are run (`Shell.swift`): no shell, explicit `PATH`, the `sudo` askpass helper (the password goes from a macOS dialog straight to `sudo`; the app never reads it);
- `valet trust` handling and anything that could widen `sudo` rights;
- the built-in phpMyAdmin installer (download over HTTPS, SHA-256 check against the official checksum, generated config);
- the update check (GitHub Releases API) and the Homebrew cask.

PureValet is ad-hoc signed and not notarized; that is a known limitation, not a vulnerability.
