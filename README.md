# Profit

A WoW Forever addon to find the most profitable profession crafts, using Auctionator's
price data (`Auctionator.API.v1`) for materials and crafted items.

## Install (beta)

Requires Auctionator. Link this repo into the beta client's AddOns folder; the link must be
named `Profit` to match `Profit.toc`:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/Profit"
```

In game, after an Auctionator scan:

- `/prof`: opens the window. Dropdowns pick the filter (Known only, the default / Known +
  trainable, which leaves out recipes only learned from patterns / Known + learnable / All
  recipes) and the profession (all, your main professions, i.e. the primary
  ones you have, or one profession); click a column to sort and a recipe for its breakdown;
  clicking a recipe you know also opens it in your profession window. The Skill column shows
  where an unlearned recipe comes from (trainer, pattern or both) and the skill to learn it.
  Recipe names are colored by skill-up chance at your skill; grey recipes are listed too,
  since they can still be profitable. The Disenchant column is the profit from disenchanting
  the crafted item instead of selling it, using the expected value of its materials.
  Enchanters also get **Disenchant from AH**: gear Auctionator has priced that's worth more
  disenchanted than it costs, leaving out items above your Enchanting skill. Clicking an item
  with the auction house open searches for it through Auctionator.
- `/prof top [count] [profession]`: most profitable known or learnable crafts, in chat
- `/prof <recipe name>`: learn level, cost, sale value after the auction house cut, vendor value, profit,
  and for green or better gear what it disenchants into and the disenchant profit
- `/prof export`: a string of your trainer, merchant and disenchant recordings to copy and share
- `/prof minimap`: show or hide the minimap button (click it to open the window, drag to move it)
- `/prof tooltip`: show or hide the estimated disenchant value in item tooltips (on by default;
  hold Shift for the materials and their chances)
- `/prof changelog`: what's new in each update (also shown once after updating)
- `/prof debug`: the client build, which game API each feature uses (MISSING if one is missing),
  and what's been detected and recorded; paste it into bug reports

Vendor-sold materials are priced at their vendor price; everything else uses Auctionator.
The addon reads your profession skills from your skill list, and which recipes you know
each time you open a profession window.

## Recipe data

`export/recipes.json` (and the addon's `Data/*.lua`) is generated from the WoW Forever client's DB2 tables, downloaded as CSV
from [wago.tools](https://wago.tools). Regenerate it after each new client build:

```sh
python3 tools/build_recipes.py            # latest Forever build on wago.tools
python3 tools/build_recipes.py --build 1.60.1.70124
```

Tables are cached in `tools/.cache/<build>/`; pass `--refresh` to re-download.

Each recipe records what it makes (and how many), its materials, required tools and
crafting station, its skill-up range, and `sources`: every way to learn it. A recipe can
have several (e.g. `["trainer", "item"]`: taught by a trainer, or learned from a pattern
bought at the auction house).

| Source | Meaning |
|---|---|
| `trainer` | Seen at a trainer in game (see below), with the skill needed to learn it; also recipes learned automatically with the profession (skill 1) |
| `item` | Taught by a recipe item (listed in `recipe_items`, with the skill needed to learn it) |
| `trainer_inferred` | Only when nothing else applies: no recipe item exists, so probably a trainer; could also be a quest or special source |
| `unknown` | Only when nothing else applies: the client data looks incomplete (see `issues`); likely not obtainable in Forever |

The client data does not include trainer skill requirements, which vendors stock an item,
or drop sources. Those fields are `null` rather than guessed, until filled in by recordings.

Items record their disenchant bracket (`disenchant`), from the client's `ItemDisenchantLoot`
table (item class, quality, item level) and its no-disenchant item flag. What each bracket
yields is a server loot table, not in the client data, so `tools/disenchant.py` keeps the
Classic results by hand, along with the Enchanting skill each bracket needs (unknown for epics
below item level 61). The top-level `disenchant` maps each bracket to its item class,
quality and item level range, its `results`, and the items in the client data in that bracket;
`no_disenchant` lists gear flagged as not disenchantable. The client data lacks many items (the
server sends them), so in game the addon matches those to a bracket from `GetItemInfo`.

## Recording trainers and merchants

The addon records into its saved variables (`ProfitDB`) whenever a window opens:

- **Trainers**: the skill needed to learn each recipe, including ones already known or not
  yet available.
- **Merchants**: items sold for gold, and whether stock is limited (usually recipe items).
- **Disenchants**: what each disenchanted item gave (counts per material). If a result isn't
  in `tools/disenchant.py`'s table for that item, or the item wasn't expected to disenchant,
  a popup asks the player to share their `/prof export`. The importer prints these as
  `unexpected:` lines; fix `tools/disenchant.py` (or the bracket data) to match.
  `/prof testdisenchant` makes the next disenchant show the popup, to try it out.

Vendor materials start from the hand-kept list in `tools/vendor_items.txt`. To ship what
you've recorded, log out (so WoW writes the saved variables), then:

```sh
python3 tools/import_recorded.py   # merges WTF/Account/*/SavedVariables/Profit.lua into export/recorded.json
python3 tools/build_recipes.py
```

Strings other players send from `/prof export` import the same way: save them to a text
file (one per line) and run `python3 tools/import_recorded.py strings.txt`.

Commit `export/recorded.json` with the regenerated data.
