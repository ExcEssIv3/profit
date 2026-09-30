"""Merge in-game recordings (ProfessionsDB SavedVariables) into export/recorded.json.

Usage: python tools/import_recorded.py [SavedVariables/Professions.lua ...]

With no arguments, reads every account's Professions.lua under the beta client's WTF folder.
Newer observations replace older ones; changed trainer skill levels are reported. Rerun
tools/build_recipes.py afterwards to ship the result.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECORDED = ROOT / "export" / "recorded.json"
WTF = Path("/Applications/World of Warcraft/_classic_beta_/WTF/Account")

TOKEN = re.compile(r"""
    \s+ | --[^\n]* |
    (?P<str>"(?:\\.|[^"\\])*") |
    (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?) |
    (?P<word>[A-Za-z_]\w*) |
    (?P<sym>[{}\[\]=,;])
""", re.VERBOSE)


def tokens(text):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"unexpected character at offset {pos}: {text[pos:pos + 20]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)


def parse_saved_variables(text):
    """Parse the `Name = value` assignments WoW writes to a SavedVariables file."""
    toks = list(tokens(text))
    i = 0

    def value():
        nonlocal i
        kind, tok = toks[i]
        i += 1
        if kind == "str":
            return json.loads(tok.replace("\\\n", "\\n"))
        if kind == "num":
            return float(tok) if any(c in tok for c in ".eE") else int(tok)
        if kind == "word":
            return {"true": True, "false": False, "nil": None}[tok]
        if tok != "{":
            raise ValueError(f"unexpected {tok!r}")
        table, n = {}, 1
        while toks[i][1] != "}":
            if toks[i][1] == "[":
                i += 1
                key = value()
                i += 2  # "]" "="
            elif toks[i][0] == "word" and toks[i + 1][1] == "=":
                key = toks[i][1]
                i += 2
            else:
                key, n = n, n + 1
            table[key] = value()
            if toks[i][1] in (",", ";"):
                i += 1
        i += 1
        return table

    result = {}
    while i < len(toks):
        name = toks[i][1]
        i += 2  # name "="
        result[name] = value()
    return result


def merge(recorded, db, source):
    changed = 0
    for section in ("trainer", "merchant"):
        for key, obs in (db.get(section) or {}).items():
            key = str(key)
            old = recorded[section].get(key)
            if old and old.get("seen", 0) >= obs.get("seen", 0):
                continue
            if section == "trainer" and old and old["skill"] != obs["skill"]:
                print(f"  trainer skill for spell {key} changed {old['skill']} -> {obs['skill']} ({source})")
            recorded[section][key] = obs
            changed += 1
    return changed


def main():
    paths = [Path(p) for p in sys.argv[1:]] or sorted(WTF.glob("*/SavedVariables/Professions.lua"))
    if not paths:
        raise SystemExit(f"no Professions.lua found under {WTF}; pass the path explicitly")
    recorded = json.loads(RECORDED.read_text(encoding="utf-8")) if RECORDED.exists() else {"trainer": {}, "merchant": {}}
    for path in paths:
        db = parse_saved_variables(path.read_text(encoding="utf-8")).get("ProfessionsDB") or {}
        print(f"{path}: {merge(recorded, db, path.parent.parent.name)} new or updated observations")
    for section in recorded:
        recorded[section] = dict(sorted(recorded[section].items(), key=lambda kv: int(kv[0])))
    RECORDED.parent.mkdir(parents=True, exist_ok=True)
    RECORDED.write_text(json.dumps(recorded, indent=1) + "\n", encoding="utf-8")
    print(f"{RECORDED}: {len(recorded['trainer'])} trainer recipes, {len(recorded['merchant'])} merchant items")


if __name__ == "__main__":
    main()
