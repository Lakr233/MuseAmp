#!/usr/bin/env python3
"""Strip stale keys from Localizable.xcstrings files and normalize source values.

For every `Localizable.xcstrings` under the project (excluding Vendor/, build/,
.build/, DerivedData/, and any SwiftPM checkouts):

  1. Remove string entries whose `extractionState` is `"stale"`.
  2. Ensure each remaining entry has a source-language localization whose
     `stringUnit.value` equals the key, with `state = "translated"`.
     This enforces the project rule that source-language values mirror the key.

The source language is discovered from the file's `sourceLanguage` field
(falling back to `"en"` if missing).

The script rewrites files in place only when content changed, preserving the
file's original trailing newline. Files are formatted with 2-space indent and
sorted `strings` keys to match Xcode's on-disk layout.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

EXCLUDE_DIR_NAMES = {
    "Vendor",
    "build",
    ".build",
    "DerivedData",
    "Pods",
    "Carthage",
    ".git",
}

DEFAULT_SOURCE_LANGUAGE = "en"


def iter_xcstrings(root: Path):
    for path in root.rglob("Localizable.xcstrings"):
        if any(part in EXCLUDE_DIR_NAMES for part in path.parts):
            continue
        yield path


def source_language(doc: dict) -> str:
    value = doc.get("sourceLanguage")
    if isinstance(value, str) and value:
        return value
    return DEFAULT_SOURCE_LANGUAGE


def normalize(doc: dict) -> tuple[dict, int, int, str]:
    """Return (new_doc, stale_removed, source_values_fixed, source_lang)."""
    strings = doc.get("strings", {})
    source_lang = source_language(doc)
    stale_removed = 0
    source_fixed = 0
    new_strings: dict = {}

    for key, entry in strings.items():
        if isinstance(entry, dict) and entry.get("extractionState") == "stale":
            stale_removed += 1
            continue

        entry = dict(entry) if isinstance(entry, dict) else {}
        localizations = dict(entry.get("localizations") or {})

        source_loc = dict(localizations.get(source_lang) or {})
        string_unit = dict(source_loc.get("stringUnit") or {})
        current_value = string_unit.get("value")
        current_state = string_unit.get("state")

        if current_value != key or current_state != "translated":
            string_unit["value"] = key
            string_unit["state"] = "translated"
            source_loc["stringUnit"] = string_unit
            localizations[source_lang] = source_loc
            source_fixed += 1

        entry["localizations"] = localizations
        new_strings[key] = entry

    new_doc = dict(doc)
    new_doc["strings"] = dict(sorted(new_strings.items(), key=lambda kv: kv[0]))
    return new_doc, stale_removed, source_fixed, source_lang


def process(path: Path) -> bool:
    original_text = path.read_text(encoding="utf-8")
    trailing_newline = original_text.endswith("\n")
    doc = json.loads(original_text)
    new_doc, stale_removed, source_fixed, source_lang = normalize(doc)

    new_text = json.dumps(
        new_doc, ensure_ascii=False, indent=2, separators=(",", " : ")
    )
    if trailing_newline:
        new_text += "\n"

    changed = new_text != original_text
    if changed:
        path.write_text(new_text, encoding="utf-8")

    status = "updated" if changed else "clean"
    print(
        f"[{status}] {path} "
        f"(source={source_lang}, stale removed: {stale_removed}, "
        f"source values fixed: {source_fixed})"
    )
    return changed


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
    if not root.exists():
        print(f"[!] path does not exist: {root}", file=sys.stderr)
        return 1

    any_changed = False
    files = list(iter_xcstrings(root))
    if not files:
        print(f"[!] no Localizable.xcstrings found under {root}")
        return 0

    for path in files:
        if process(path):
            any_changed = True

    if any_changed:
        print("[*] done (changes written)")
    else:
        print("[*] done (no changes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
