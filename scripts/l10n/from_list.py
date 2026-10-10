#!/usr/bin/env python3
"""Turn an ordered list of translations into <target>/<lang>.json.

Usage: from_list.py <target> <lang>   (reads <target>/<lang>.list.json)
The list must follow <target>/keys.json order. Format specifiers are checked.
"""
import json, re, sys, pathlib
here = pathlib.Path(__file__).parent
target, lang = sys.argv[1], sys.argv[2]
keys = json.loads((here / target / "keys.json").read_text())
txt = here / target / f"{lang}.list.txt"
if txt.exists():
    entries = {}
    for line in txt.read_text().splitlines():
        if not line.strip():
            continue
        idx, text = line.split("|", 1)
        entries[int(idx)] = text.replace("\\n", "\n")
    missing = [i for i in range(len(keys)) if i not in entries]
    assert not missing, f"missing indexes: {missing}"
    values = [entries[i] for i in range(len(keys))]
    list_file = txt
else:
    list_file = here / target / f"{lang}.list.json"
    values = json.loads(list_file.read_text())
assert len(keys) == len(values), f"{len(keys)} keys vs {len(values)} values"
spec = re.compile(r"%(?:\d+\$)?(?:lld|@|%)")
def norm(s): return sorted(re.sub(r"\d+\$", "", m) for m in spec.findall(s))
bad = [(k, v) for k, v in zip(keys, values) if norm(k) != norm(v)]
for k, v in bad: print("SPEC MISMATCH:", k, "=>", v)
assert not bad
(here / target / f"{lang}.json").write_text(json.dumps(dict(zip(keys, values)), ensure_ascii=False, indent=0))
list_file.unlink()
print(lang, target, "ok", len(keys))
