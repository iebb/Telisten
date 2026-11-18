#!/usr/bin/env python3
"""Apply the reviewed translation fixes to Telisten/Localizable.xcstrings.

Run from the repo root: python3 docs/copy/translation-pass/apply.py
Only overwrites the listed language values for keys that exist; never adds keys
(so a removed key such as "Order" is not brought back). Prints anything skipped.
Keeps the catalog's existing JSON layout byte-for-byte (2-space indent, UTF-8).
"""
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[3]
cat_path = root / "Telisten/Localizable.xcstrings"
changes = json.loads((pathlib.Path(__file__).parent / "changes.json").read_text())
raw = cat_path.read_text()
cat = json.loads(raw)
applied = skipped = 0
for lang, entries in changes.items():
    for key, value in entries.items():
        loc = cat["strings"].get(key, {}).get("localizations", {}).get(lang, {}).get("stringUnit")
        if loc is None:
            print(f"skip {lang}: {key!r} (key or language missing)"); skipped += 1; continue
        loc["value"] = value
        loc["state"] = "translated"
        applied += 1
out = json.dumps(cat, ensure_ascii=False, indent=2, separators=(",", ": "))
cat_path.write_text(out + ("\n" if raw.endswith("\n") else ""))
print(f"applied {applied}, skipped {skipped}")
sys.exit(0)
