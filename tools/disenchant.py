"""Classic disenchant results, which are server loot tables and not in the client data.

The client's ItemDisenchantLoot table gives the brackets (item class, quality, item level range);
this gives what each bracket yields. Keyed by (quality, item class, bracket MinLevel) as in
ItemDisenchantLoot; each result is (chance %, min count, max count, item name).
Source: warcraft.wiki.gg/wiki/Disenchanting_tables (Classic rows). Check in game if Forever changes them.
"""

UNCOMMON, RARE, EPIC = 2, 3, 4
WEAPON, ARMOR = 2, 4

# Uncommon brackets: (min level, dust, dust counts, essence, essence counts, shard)
_UNCOMMON = [
    (5, "Strange Dust", (1, 2), "Lesser Magic Essence", (1, 2), None),
    (16, "Strange Dust", (2, 3), "Greater Magic Essence", (1, 2), "Small Glimmering Shard"),
    (21, "Strange Dust", (4, 6), "Lesser Astral Essence", (1, 2), "Small Glimmering Shard"),
    (26, "Soul Dust", (1, 2), "Greater Astral Essence", (1, 2), "Large Glimmering Shard"),
    (31, "Soul Dust", (2, 5), "Lesser Mystic Essence", (1, 2), "Small Glowing Shard"),
    (36, "Vision Dust", (1, 2), "Greater Mystic Essence", (1, 2), "Large Glowing Shard"),
    (41, "Vision Dust", (2, 5), "Lesser Nether Essence", (1, 2), "Small Radiant Shard"),
    (46, "Dream Dust", (1, 2), "Greater Nether Essence", (1, 2), "Large Radiant Shard"),
    (51, "Dream Dust", (2, 5), "Lesser Eternal Essence", (1, 2), "Small Brilliant Shard"),
    (56, "Illusion Dust", (1, 2), "Greater Eternal Essence", (1, 2), "Large Brilliant Shard"),
    (61, "Illusion Dust", (2, 5), "Greater Eternal Essence", (2, 3), "Large Brilliant Shard"),
]


def _uncommon_chances(cls, level):
    """(dust %, essence %, shard %). Armor is mostly dust, weapons mostly essence."""
    if level == 5:
        dust, essence, shard = 80, 20, 0
    elif level == 21:
        dust, essence, shard = 75, 15, 10
    elif level >= 51 and cls == WEAPON:
        return 22, 75, 3
    else:
        dust, essence, shard = 75, 20, 5
    return (dust, essence, shard) if cls == ARMOR else (essence, dust, shard)


TABLE = {}
for cls in (WEAPON, ARMOR):
    for level, dust, dust_n, essence, essence_n, shard in _UNCOMMON:
        d, e, s = _uncommon_chances(cls, level)
        results = [(d, *dust_n, dust), (e, *essence_n, essence)]
        if shard:
            results.append((s, 1, 1, shard))
        TABLE[(UNCOMMON, cls, level)] = results

    for level, shard in [(5, "Small Glimmering Shard"), (16, "Small Glimmering Shard"),
                         (21, "Small Glimmering Shard"), (26, "Large Glimmering Shard"),
                         (31, "Small Glowing Shard"), (36, "Large Glowing Shard"), (41, "Small Radiant Shard"),
                         (46, "Large Radiant Shard"), (51, "Small Brilliant Shard")]:
        TABLE[(RARE, cls, level)] = [(100, 1, 1, shard)]
    for level in (56, 61):
        TABLE[(RARE, cls, level)] = [(99.5, 1, 1, "Large Brilliant Shard"), (0.5, 1, 1, "Nexus Crystal")]

    TABLE[(EPIC, cls, 40)] = [(100, 2, 4, "Small Radiant Shard")]
    TABLE[(EPIC, cls, 46)] = [(100, 2, 4, "Large Radiant Shard")]
    TABLE[(EPIC, cls, 51)] = [(100, 2, 4, "Small Brilliant Shard")]
    TABLE[(EPIC, cls, 56)] = [(100, 1, 1, "Nexus Crystal")]
    TABLE[(EPIC, cls, 61)] = [(100, 1, 2, "Nexus Crystal")]


def required_skill(quality, min_level):
    """Enchanting skill needed to disenchant a bracket, or None if unknown.
    Source: warcraft.wiki.gg/wiki/Disenchanting. It gives no skill for epics below item level 61."""
    if quality == EPIC:
        return 225 if min_level >= 61 else None
    steps = [(21, 25), (26, 50), (31, 75), (36, 100), (41, 125), (46, 150), (51, 175), (56, 200), (61, 225)]
    skill = 1 if quality == UNCOMMON else 25  # rares up to item level 25 need 25
    for level, needed in steps:
        if min_level >= level:
            skill = needed
    return skill
