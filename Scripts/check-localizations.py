#!/usr/bin/env python3
"""Validate the shipped Apple and Android localization catalogs."""

import json
import re
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
LOCALES = {"en", "zh-Hans", "zh-Hant", "ja", "vi", "fr", "es", "ko"}
ANDROID_DIRS = {
    "en": "values",
    "zh-Hans": "values-b+zh+Hans",
    "zh-Hant": "values-b+zh+Hant",
    "ja": "values-ja",
    "vi": "values-vi",
    "fr": "values-fr",
    "es": "values-es",
    "ko": "values-ko",
}
FORMAT = re.compile(r"%(?:\d+\$)?(?:lld|ld|@|s|d|f)")
SIMPLIFIED_ONLY = set("这还们里发后对点门开过时会个听说话关进边线让记离应续从请误验码")
TRADITIONAL_ONLY = set("這還們裡發後對點門開過時會個聽說話關進邊線讓記離應續從請誤驗碼錄機體讀寫儲訊載與為網")


def placeholders(value: str) -> Counter[str]:
    return Counter(FORMAT.findall(value))


def main() -> None:
    catalog = json.loads((ROOT / "Telisten/Localizable.xcstrings").read_text())
    assert catalog["sourceLanguage"] == "en"
    for key, entry in catalog["strings"].items():
        values = entry["localizations"]
        assert set(values) == LOCALES, f"Missing Apple locale for {key!r}"
        for locale, translation in values.items():
            value = translation["stringUnit"]["value"]
            assert value.strip() or not key.strip(), (locale, key, "Empty translation")
            assert not key.isspace() or value == key, (locale, key, "Whitespace changed")
            if "Telisten" in key:
                assert "Telisten" in value, (locale, key, "App name changed")
            if "_Playlist" in key:
                assert "_Playlist" in value, (locale, key, "Folder name changed")
            if locale == "zh-Hant":
                assert not SIMPLIFIED_ONLY.intersection(value), (locale, key, "Simplified Chinese characters")
            if locale == "zh-Hans":
                assert not TRADITIONAL_ONLY.intersection(value), (locale, key, "Traditional Chinese characters")
            assert placeholders(value) == placeholders(key), (locale, key, value)

    swift_source = "\n".join(path.read_text() for path in (ROOT / "Telisten").rglob("*.swift"))
    swift_literals = re.findall(
        r'\b(?:Text|Button|Label|Section|Toggle|LabeledContent|Picker|TextField|SecureField|ContentUnavailableView|navigationTitle|accessibilityLabel|accessibilityHint|help)\s*\(\s*"((?:\\.|[^"\\])*)"',
        swift_source,
    )
    missing = {
        value.replace("\\n", "\n")
        for value in swift_literals
        if value.strip() and "\\(" not in value and not value.startswith(("http", "system."))
        and value.replace("\\n", "\n") not in catalog["strings"]
    }
    assert not missing, f"Missing SwiftUI keys: {sorted(missing)}"

    baseline = None
    for locale, directory in ANDROID_DIRS.items():
        path = ROOT / "android/app/src/main/res" / directory / "strings.xml"
        resources = ElementTree.parse(path).getroot()
        entries = {(element.tag, element.attrib["name"]): element for element in resources}
        assert len(entries) == len(resources), f"Duplicate Android resource in {path}"
        if baseline is None:
            baseline = entries
        else:
            assert set(entries) == set(baseline), f"Missing Android resource in {path}"
            for name, entry in entries.items():
                original = baseline[name]
                if entry.tag == "string":
                    assert (entry.text or "").strip() or not (original.text or "").strip(), (locale, name, "Empty translation")
                    if "Telisten" in (original.text or ""):
                        assert "Telisten" in (entry.text or ""), (locale, name, "App name changed")
                    if "_Playlist" in (original.text or ""):
                        assert "_Playlist" in (entry.text or ""), (locale, name, "Folder name changed")
                    if locale == "zh-Hant":
                        assert not SIMPLIFIED_ONLY.intersection(entry.text or ""), (locale, name, "Simplified Chinese characters")
                    if locale == "zh-Hans":
                        assert not TRADITIONAL_ONLY.intersection(entry.text or ""), (locale, name, "Traditional Chinese characters")
                    assert placeholders(entry.text or "") == placeholders(original.text or ""), (locale, name)
                else:
                    assert {item.attrib["quantity"] for item in entry} == {"one", "other"}, (locale, name)
                    for item, source in zip(entry, original):
                        assert placeholders(item.text or "") == placeholders(source.text or ""), (locale, name)

    lookup = (ROOT / "android/app/src/main/java/ad/neko/telisten/L10n.kt").read_text()
    referenced = set(re.findall(r"R\.string\.(l10n_[a-z0-9_]+)", lookup))
    resources = {name for kind, name in baseline if kind == "string"}
    assert referenced == resources, f"Android lookup mismatch: {sorted(referenced ^ resources)}"
    for path in (ROOT / "android/app/src/main/java/ad/neko/telisten").rglob("*.kt"):
        source = path.read_text()
        for key in re.findall(r'\b(?:tr\(\s*|localize\(\s*[^,]+,\s*)"([^"\n]+)"', source):
            assert f'"{key}" -> R.string.' in lookup, (path, key, "Missing Android lookup")

    print(f"Validated {len(catalog['strings'])} Apple and {len(baseline)} Android entries in 8 languages")


if __name__ == "__main__":
    main()
