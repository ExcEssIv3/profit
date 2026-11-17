# Profit

Profit shows which of your profession crafts actually make gold. It combines Auctionator's auction house prices with recipe data from WoW Forever to show, for every recipe:

*   **Material cost**, using auction prices, vendor prices for vendor-bought materials like thread, dye and vials, or the crafting cost of materials you can make yourself (like bolts of cloth) when that's cheaper
*   **What it sells for** after the auction house cut, and a warning when a vendor would pay more
*   **Profit** per craft, and as a **%** of the cost, to pick crafts when you have little gold to spend
*   **Craft** dropdown: make the materials you can make when it's cheapest, only when it gives more gold per hour, or never
*   **Gold per hour** for a batch of crafts, counting the cast times of the recipe and of the materials you make yourself, with a warning when the auction house didn't have enough of a material in your last scan
*   **Market depth**: a batch's materials are priced from every auction Profit has seen (in a full scan with Auctionator's slower scan mode, when you select the material in Auctionator's search results, or with **Scan materials**, which searches the materials of the listed recipes one at a time), cheapest first, not just the lowest price, so one cheap listing doesn't throw off the numbers
*   **Vendor flips**: rank crafts by what a vendor pays instead of the auction house, or by whichever pays more
*   **Skill color** at your current level (grey recipes are included, since they can still be profitable)
*   **Where to learn it** if you don't know it yet: trainer (with the skill needed), pattern or recipe item (with its vendor or auction price), or both, plus where it drops, which vendor sells it, or which quest gives it
*   **Disenchant profit**: what you'd make crafting the item to disenchant instead of selling it

## Disenchanting

*   **Item tooltips** show the estimated disenchant value of green, blue and epic weapons and armor, based on the auction prices of the materials. Hold **Shift** to see each material with its chance and price.
*   **Craft costs in tooltips:** any item a profession makes shows what it costs to craft, using the cheapest recipe you know (or the cheapest of any, marked "not known"). Hold **Shift** for the reagents and the profit from selling it on the auction house.
*   **Disenchant from AH** (enchanters only): a list of gear on the auction house that's worth more disenchanted than it costs, leaving out items above your Enchanting skill. Click an item with the auction house open to search for it.
*   Recipe details show what crafted gear disenchants into, and say when disenchanting beats selling.

## How to use

1.  Install **Auctionator** (required) and run a scan at the auction house.
2.  Open each of your profession windows once so Profit knows your skill and recipes.
3.  Type **/prof**, or click the minimap button.

In the window you can filter to recipes you know, recipes you know plus ones a trainer teaches at your skill, recipes you can learn now, all recipes, or your favorites; pick one profession or your main professions; choose whether to sell on the auction house, to a vendor, or wherever pays more; search; and sort by any column. Click a recipe for its full breakdown. If you know it, the recipe also opens in your profession window. Click the star to the left of a recipe to add it to your favorites. **Shopping list** under the details creates an Auctionator shopping list with the materials for as many crafts as you enter; materials you can make yourself (like bolts of cloth) are replaced by what they're made from when making that many is cheaper than buying them, and vendor materials are listed in chat. The crafted item is added last, without a quantity, so searching the list also refreshes what it sells for.

## Commands

*   `/prof`: open the window
*   `/prof top [count] [profession]`: most profitable crafts, in chat
*   `/prof <recipe>`: breakdown of one recipe
*   `/prof minimap`: show or hide the minimap button
*   `/prof tooltip`: show or hide disenchant values and craft costs in item tooltips
*   `/prof export`: share what you've recorded (see below)
*   `/prof changelog`: what's new in each update
*   `/prof debug`: details to include in a bug report

## Help fill in the data

Some information isn't in the game files, like the skill needed to learn trainer recipes, which vendors sell what, and what disenchanting gives. Profit records this automatically when you open trainer and merchant windows and when you disenchant. When the data is missing, Profit says so instead of guessing. If a disenchant gives something Profit didn't expect, a popup asks you to share it. To help everyone, type `/prof export`, copy the text, and post it at [github.com/ExcEssIv3/profit/issues](https://github.com/ExcEssIv3/profit/issues).

## Notes

*   Built for WoW Forever. Please report any issues.
*   English clients only for now.
*   Faction auction houses only (5% cut).
*   Disenchant results use the Classic loot tables; WoW Forever may differ, which is why Profit records what your disenchants actually give.