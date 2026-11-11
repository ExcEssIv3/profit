"""Server hotfixes that the client DB2 tables don't have yet, kept by hand.

Blizzard hotfixes reach the client's cache, not the build's tables on wago.tools, until a later
build ships them. build_recipes.py applies these on top of the client data and warns when the
client already agrees, so the entry can be removed.
Source: https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-10-2026
"""

# Item ID -> fields of an export/recipes.json item.
ITEMS = {
    247754: {"sell_price": 5},  # Minor Arcane Elixir, Nov 10 (was 25)
    4390: {"sell_price": 125},  # Iron Grenade, Nov 10 (was 5 silver)
    21547: {"name": "Recipe: Elixir of Holy Power"},  # Nov 10 (was "...Greater Firepower")
}

# Recipe spell ID -> skill fields ("learn", "yellow", "grey") or "tools".
# "learn" also sets the skill on the recipe's items.
RECIPES = {
    3326: {"grey": 90},  # Coarse Grinding Stone, Nov 10 (was 75)
    1263031: {"learn": 125, "yellow": 125, "grey": 130},  # Tanning Rack, Nov 6 (was 140/140/145)
    1263056: {"tools": ["Runed Golden Rod"]},  # Arcane Salvager, Nov 10 (was Runed Truesilver Rod)
}
