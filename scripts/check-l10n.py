#!/usr/bin/env python3
"""Checks that every localizable string literal in Sources/ has a French translation.

Usage: python3 scripts/check-l10n.py [--list]
English is the development language (the keys are the English strings), so only
Resources/fr.lproj/Localizable.strings needs entries. Exit code 1 if a key is missing.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALLS = r"(?:(?:Text|Button|Label|Menu|Toggle|Link|LabeledContent|Section|TextField|ContentUnavailableView|LocalizedStringKey|\.help|\.navigationTitle)\(\s*|String\(localized:\s*)"


def literals(source: str):
    """Yields localizable literals, with Swift interpolations turned into %@."""
    for match in re.finditer(CALLS + '"', source):
        i, out, depth = match.end(), [], 0
        while i < len(source):
            c = source[i]
            if c == "\\" and source[i + 1] == "(":
                depth, i = 1, i + 2
                while depth:
                    depth += {"(": 1, ")": -1}.get(source[i], 0)
                    i += 1
                out.append("%@")
                continue
            if c == "\\":
                out.append(source[i:i + 2])
                i += 2
                continue
            if c == '"':
                break
            out.append(c)
            i += 1
        yield "".join(out)


def main() -> int:
    keys = set()
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        keys.update(literals(path.read_text()))
    strings = ROOT / "Resources/fr.lproj/Localizable.strings"
    raw = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(strings)], capture_output=True, text=True, check=True).stdout
    import json
    translated = set(json.loads(raw))
    if "--list" in sys.argv:
        print("\n".join(sorted(keys)))
        return 0
    # Swift keys contain escapes like \n; the .strings file stores real newlines.
    decoded = {k.encode().decode("unicode_escape") if "\\" in k else k: k for k in keys}
    missing = sorted(orig for real, orig in decoded.items() if real not in translated)
    unused = sorted(translated - set(decoded))
    for key in missing:
        print(f"missing fr: {key}")
    for key in unused:
        print(f"unused fr:  {key}")
    print(f"{len(keys)} keys, {len(missing)} missing, {len(unused)} unused")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
