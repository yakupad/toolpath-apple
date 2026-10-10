#!/usr/bin/env python3
"""Merge translation JSON files (scripts/l10n/<lang>.json) into a String Catalog.

Usage: apply.py <catalog.xcstrings> <translations-dir> <lang> [<lang> ...]
Keys missing from a translation file are left untranslated (fall back to English).
"""
import json
import pathlib
import sys

catalog_path = pathlib.Path(sys.argv[1])
catalog = json.loads(catalog_path.read_text())
here = pathlib.Path(__file__).parent / sys.argv[2]
for lang in sys.argv[3:]:
    translations = json.loads((here / f"{lang}.json").read_text())
    for key, entry in catalog["strings"].items():
        if key in translations:
            entry.setdefault("localizations", {})[lang] = {
                "stringUnit": {"state": "translated", "value": translations[key]}
            }
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
