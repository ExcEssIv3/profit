# professions

A WoW Forever addon to find the most profitable profession crafts, using Auctionator's
price data (`Auctionator.API.v1`) for materials and crafted items.

## Install (beta)

Requires Auctionator. Link this repo into the beta client's AddOns folder; the link must be
named `Professions` to match `Professions.toc`:

```sh
ln -s "$PWD" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/Professions"
```

In game, after an Auctionator scan:

- `/prof top [count] [profession]`: most profitable crafts that have prices for every item
- `/prof <recipe name>`: learn level, cost, sale value after the auction house cut, vendor value and profit

Vendor-sold materials are priced at their vendor price; everything else uses Auctionator.

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

## Recording trainers and merchants

The addon records into its saved variables (`ProfessionsDB`) whenever a window opens:

- **Trainers**: the skill needed to learn each recipe, including ones already known or not
  yet available.
- **Merchants**: items sold for gold, and whether stock is limited (usually recipe items).

Vendor materials start from the hand-kept list in `tools/vendor_items.txt`. To ship what
you've recorded, log out (so WoW writes the saved variables), then:

```sh
python3 tools/import_recorded.py   # merges WTF/Account/*/SavedVariables/Professions.lua into export/recorded.json
python3 tools/build_recipes.py
```

Commit `export/recorded.json` with the regenerated data.
