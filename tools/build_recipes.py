"""Build export/recipes.json and the addon's Data/*.lua from WoW Forever client DB2 tables.

For each profession recipe: what it makes, its materials, required tools and
crafting station, skill-up range, and where it is learned. Anything the client
data cannot tell us is left null or marked "unknown" rather than guessed.

Usage: python tools/build_recipes.py [--build 1.60.1.70124] [--refresh]
"""

import argparse
import json
from collections import defaultdict
from pathlib import Path

import db2
from disenchant import TABLE as DISENCHANT_TABLE, required_skill

PROFESSIONS = {
    "164": "Blacksmithing",
    "165": "Leatherworking",
    "171": "Alchemy",
    "185": "Cooking",
    "186": "Mining",
    "197": "Tailoring",
    "202": "Engineering",
    "333": "Enchanting",
    "129": "First Aid",
}

ITEM_CLASS_RECIPE = "9"
RECIPE_SUBCLASS_BOOK = "0"  # class skill books, not profession recipes
ITEM_TRIGGER_LEARN = "6"  # item effect teaches its SpellID directly (Classic style)
EFFECT_CREATE_ITEM = "24"
EFFECT_LEARN_SPELL = "36"
ACQUIRE_ON_SKILL_LEARN = "1"
ITEM_FLAG_NO_DISENCHANT = 0x8000  # ItemSparse Flags_0, e.g. enchanting wands, PvP rewards

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "export" / "recipes.json"
RECORDED = ROOT / "export" / "recorded.json"  # written by tools/import_recorded.py
VENDOR_ITEMS = Path(__file__).resolve().parent / "vendor_items.txt"
LUA_DIR = ROOT / "Data"


def build(build_id, refresh=False):
    def t(name):
        return db2.load(name, build_id, refresh)

    items = {r["ID"]: r for r in t("Item")}
    sparse = {r["ID"]: r for r in t("ItemSparse")}
    spell_names = {r["ID"]: r["Name_lang"] for r in t("SpellName")}
    reagents = {r["SpellID"]: r for r in t("SpellReagents")}
    item_effects = {r["ID"]: r for r in t("ItemEffect")}
    totem_cats = {r["ID"]: r["Name_lang"] for r in t("TotemCategory")}
    focus_names = {r["ID"]: r["Name_lang"] for r in t("SpellFocusObject")}

    creates = {}  # spell -> (item id, count)
    learn_spells = defaultdict(set)  # "learn" spell -> spells it teaches
    for r in t("SpellEffect"):
        if r["Effect"] == EFFECT_CREATE_ITEM and r["EffectItemType"] != "0":
            creates[r["SpellID"]] = (r["EffectItemType"], max(1, round(float(r["EffectBasePointsF"]))))
        elif r["Effect"] == EFFECT_LEARN_SPELL and r["EffectTriggerSpell"] != "0":
            learn_spells[r["SpellID"]].add(r["EffectTriggerSpell"])

    taught_by = defaultdict(set)  # recipe spell -> recipe item ids
    for x in t("ItemXItemEffect"):
        item, eff = items.get(x["ItemID"]), item_effects.get(x["ItemEffectID"])
        if not item or not eff or item["ClassID"] != ITEM_CLASS_RECIPE or item["SubclassID"] == RECIPE_SUBCLASS_BOOK:
            continue
        if eff["TriggerType"] == ITEM_TRIGGER_LEARN:
            taught_by[eff["SpellID"]].add(x["ItemID"])
        for s in learn_spells.get(eff["SpellID"], ()):
            taught_by[s].add(x["ItemID"])

    tools = {}
    for r in t("SpellTotems"):
        names = [totem_cats.get(r[f"RequiredTotemCategoryID_{i}"]) for i in (0, 1) if r[f"RequiredTotemCategoryID_{i}"] != "0"]
        names += [item_name(sparse, r[f"Totem_{i}"]) for i in (0, 1) if r[f"Totem_{i}"] != "0"]
        tools[r["SpellID"]] = names
    stations = {
        r["SpellID"]: focus_names.get(r["RequiresSpellFocus"])
        for r in t("SpellCastingRequirements")
        if r["RequiresSpellFocus"] != "0"
    }

    recorded = load_recorded()
    vendor = vendor_items(sparse, recorded)

    recipes, used_items = [], set()
    for r in t("SkillLineAbility"):
        prof, spell = PROFESSIONS.get(r["SkillLine"]), r["Spell"]
        if not prof or spell not in reagents:
            continue
        g = reagents[spell]
        mats = [
            {"item": int(g[f"Reagent_{i}"]), "count": int(g[f"ReagentCount_{i}"])}
            for i in range(8)
            if g[f"Reagent_{i}"] != "0"
        ]
        issues = []
        if any(str(m["item"]) not in sparse for m in mats):
            # Seen on leftover Season of Discovery recipes; likely not obtainable in Forever.
            issues.append("unnamed_reagent")

        recipe_items = [
            {"item": int(i), "learn_skill": int(sparse[i]["RequiredSkillRank"])}
            for i in sorted(taught_by.get(spell, ()), key=int)
            if is_live_item(sparse, i)
        ]
        trainer = recorded["trainer"].get(spell)  # seen at a trainer in game
        # Recipes learned automatically with the profession are treated as trainer-taught at skill 1.
        if not trainer and r["AcquireMethod"] == ACQUIRE_ON_SKILL_LEARN:
            trainer = {"skill": 1}
        # Every way to learn it; a recipe can be both taught by a trainer and sold as an item.
        sources = [name for name, found in (("trainer", trainer), ("item", recipe_items)) if found]
        if issues and not trainer:
            sources = ["unknown"]
        elif not sources:
            sources = ["trainer_inferred"]  # no recipe item; could also be a quest or other special source
        learn_levels = [ri["learn_skill"] for ri in recipe_items]
        if trainer:
            learn_levels.append(trainer["skill"])

        out = creates.get(spell)
        yellow, grey = int(r["TrivialSkillLineRankLow"]), int(r["TrivialSkillLineRankHigh"])
        recipes.append({
            "spell": int(spell),
            "name": spell_names.get(spell),
            "profession": prof,
            "makes": {"item": int(out[0]), "count": out[1]} if out else None,
            "reagents": mats,
            "tools": tools.get(spell, []),
            "station": stations.get(spell),
            "skill": {
                # Lowest skill it can be learned at (orange starts here); null until a trainer
                # recipe has been recorded in game.
                "learn": min(learn_levels) if learn_levels else None,
                "trainer": trainer["skill"] if trainer else None,
                "yellow": yellow or None,
                "grey": grey or None,
            },
            "sources": sources,
            "recipe_items": recipe_items,
            "issues": issues,
        })
        used_items.update(m["item"] for m in mats)
        used_items.update(ri["item"] for ri in recipe_items)
        if out:
            used_items.add(int(out[0]))

    recipes.sort(key=lambda x: (x["profession"], x["skill"]["yellow"] or 0, x["name"] or ""))
    # Every item that can be disenchanted, not just recipe items, for the item tooltip.
    # The client's ItemSparse lacks many items (the server sends them); the addon works those
    # out in game from the bracket ranges, so it also needs the items flagged no-disenchant.
    brackets, disenchant = disenchant_brackets(t("ItemDisenchantLoot"), sparse)
    item_bracket, no_disenchant = {}, []
    for i in sparse:
        if not is_live_item(sparse, i):
            continue
        bracket = disenchant_bracket(items.get(i), sparse[i], brackets)
        if bracket:
            item_bracket[i] = bracket
        elif disenchant_bracket(items.get(i), sparse[i], brackets, ignore_flag=True):
            no_disenchant.append(int(i))
    for results in disenchant.values():
        used_items.update(r["item"] for r in results)
    item_table = {
        str(i): {
            "name": sparse[str(i)]["Display_lang"],
            "quality": int(sparse[str(i)]["OverallQualityID"]),
            # Copper per item. The client's BuyPrice is for a vendor stack (e.g. 5 vials).
            "buy_price": unit_price(sparse[str(i)]),
            "sell_price": int(sparse[str(i)]["SellPrice"]),
            # "unlimited" (priced at buy_price), "limited" (e.g. vendor recipes), or null.
            "vendor": vendor.get(str(i)),
            # ItemDisenchantLoot bracket ID, a key of "disenchant"; null if it can't be disenchanted.
            "disenchant": item_bracket.get(str(i)),
        }
        for i in sorted(used_items)
        if str(i) in sparse
    }
    by_bracket = defaultdict(list)
    for i, bracket in item_bracket.items():
        by_bracket[bracket].append(int(i))
    ranges = {b["ID"]: b for b in brackets}
    return {"build": build_id, "recipes": recipes, "items": item_table,
            "disenchant": {b: {"class": int(ranges[b]["Class"]), "quality": int(ranges[b]["Quality"]),
                               "min_level": int(ranges[b]["MinLevel"]), "max_level": int(ranges[b]["MaxLevel"]),
                               "skill": required_skill(int(ranges[b]["Quality"]), int(ranges[b]["MinLevel"])),
                               "results": disenchant[b], "items": sorted(by_bracket[b])}
                           for b in sorted(disenchant, key=int)},
            "no_disenchant": sorted(no_disenchant)}


def disenchant_brackets(rows, sparse):
    """Client bracket rows, and bracket ID -> [{item, chance, min, max}] from tools/disenchant.py."""
    by_name = {}
    for item_id, row in sparse.items():
        by_name.setdefault(row["Display_lang"], int(item_id))
    brackets, results = [], {}
    for r in rows:
        if r["Subclass"] != "-1":
            raise SystemExit(f"disenchant bracket {r['ID']} is for one item subclass; the addon assumes all")
        key = (int(r["Quality"]), int(r["Class"]), int(r["MinLevel"]))
        if key not in DISENCHANT_TABLE:
            print(f"  warning: no disenchant results for bracket {r['ID']} {key}; its items are left out")
            continue
        brackets.append(r)
        results[r["ID"]] = [
            {"item": by_name[name], "chance": chance, "min": low, "max": high}
            for chance, low, high, name in DISENCHANT_TABLE[key]
        ]
    return brackets, results


def disenchant_bracket(item, row, brackets, ignore_flag=False):
    if not item or not row or (not ignore_flag and int(row["Flags_0"]) & ITEM_FLAG_NO_DISENCHANT):
        return None
    level = int(row["ItemLevel"])
    for b in brackets:
        if (b["Class"] == item["ClassID"] and b["Quality"] == row["OverallQualityID"]
                and b["Subclass"] in ("-1", item["SubclassID"]) and int(b["MinLevel"]) <= level <= int(b["MaxLevel"])):
            return b["ID"]
    return None


def load_recorded():
    if not RECORDED.exists():
        return {"trainer": {}, "merchant": {}}
    return json.loads(RECORDED.read_text(encoding="utf-8"))


def vendor_items(sparse, recorded):
    """Item ID -> "unlimited" | "limited", from vendor_items.txt plus merchants seen in game."""
    by_name = defaultdict(list)
    for item_id, row in sparse.items():
        by_name[row["Display_lang"]].append(item_id)
    vendor = {}
    for line in VENDOR_ITEMS.read_text(encoding="utf-8").splitlines():
        name = line.split("#", 1)[0].strip()
        if not name:
            continue
        ids = by_name.get(name)
        if not ids:
            raise SystemExit(f"{VENDOR_ITEMS.name}: no item named {name!r} in this build")
        for item_id in ids:
            vendor[item_id] = "unlimited"
    for item_id, seen in recorded["merchant"].items():
        if not seen.get("limited"):
            vendor[item_id] = "unlimited"
        else:
            vendor.setdefault(item_id, "limited")
    return vendor


def unit_price(row):
    price = int(row["BuyPrice"]) / max(int(row["VendorStackCount"]), 1)
    return int(price) if price.is_integer() else round(price, 2)


def item_name(sparse, item_id):
    return sparse.get(item_id, {}).get("Display_lang") or f"<item {item_id}>"


def is_live_item(sparse, item_id):
    """Drop recipe items the client keeps but that are not in the game (no name, or 'Deprecated')."""
    name = sparse.get(item_id, {}).get("Display_lang")
    return bool(name) and not name.startswith("Deprecated")


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_list(values):
    return "{" + ",".join(str(v) for v in values) + "}"


def write_lua(data):
    """Write the addon's compact data files. See Core.lua for the field meanings."""
    header = f"-- Generated by tools/build_recipes.py from client build {data['build']}. Do not edit.\n"
    lines = [header, "local _, ns = ...", f"ns.DataBuild = {lua_str(data['build'])}", "ns.Recipes = {"]
    for r in data["recipes"]:
        fields = [f"n={lua_str(r['name'] or '')}", f"p={lua_str(r['profession'])}",
                  "s={" + ",".join(lua_str(src) for src in r["sources"]) + "}"]
        if r["makes"]:
            fields.append(f"m={lua_list([r['makes']['item'], r['makes']['count']])}")
        fields.append("r=" + lua_list(v for m in r["reagents"] for v in (m["item"], m["count"])))
        skill = r["skill"]
        for key, val in (("l", skill["learn"]), ("t", skill["trainer"]), ("y", skill["yellow"]), ("g", skill["grey"])):
            if val is not None:
                fields.append(f"{key}={val}")
        if r["recipe_items"]:
            fields.append("ri=" + lua_list(v for ri in r["recipe_items"] for v in (ri["item"], ri["learn_skill"])))
        if r["issues"]:
            fields.append("x=" + "{" + ",".join(lua_str(i) for i in r["issues"]) + "}")
        lines.append(f"  [{r['spell']}]={{{','.join(fields)}}},")
    lines.append("}")

    item_lines = [header, "local _, ns = ...", "ns.Items = {"]
    for item_id, it in data["items"].items():
        vendor = {"unlimited": ",vs=1", "limited": ",vl=1"}.get(it["vendor"], "")
        item_lines.append(f"  [{item_id}]={{n={lua_str(it['name'])},q={it['quality']},b={it['buy_price']},v={it['sell_price']}{vendor}}},")
    item_lines.append("}")

    de_lines = [header, "local _, ns = ...", "ns.Disenchant = {"]
    for bracket, de in data["disenchant"].items():
        values = (v for r in de["results"] for v in (r["item"], r["chance"], r["min"], r["max"]))
        skill = f"s={de['skill']}," if de["skill"] is not None else ""
        de_lines.append(f"  [{bracket}]={{c={de['class']},q={de['quality']},lo={de['min_level']},hi={de['max_level']},{skill}"
                        f"r={lua_list(values)},i={lua_list(de['items'])}}},")
    de_lines.append("}")
    de_lines.append(f"ns.NoDisenchant = {lua_list(data['no_disenchant'])}")

    LUA_DIR.mkdir(exist_ok=True)
    (LUA_DIR / "Recipes.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (LUA_DIR / "Items.lua").write_text("\n".join(item_lines) + "\n", encoding="utf-8")
    (LUA_DIR / "Disenchant.lua").write_text("\n".join(de_lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", help="client build (default: latest Forever build on wago.tools)")
    ap.add_argument("--refresh", action="store_true", help="re-download cached tables")
    args = ap.parse_args()

    build_id = args.build or db2.latest_build()
    data = build(build_id, args.refresh)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    write_lua(data)

    by_source = defaultdict(int)
    for r in data["recipes"]:
        by_source["+".join(r["sources"])] += 1
    disenchantable = sum(len(de["items"]) for de in data["disenchant"].values())
    print(f"build {build_id}: {len(data['recipes'])} recipes, {len(data['items'])} items "
          f"({disenchantable} disenchantable in the game) -> {OUT}, {LUA_DIR}/")
    print("  " + ", ".join(f"{k}={v}" for k, v in sorted(by_source.items())))


if __name__ == "__main__":
    main()
