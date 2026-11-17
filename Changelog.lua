local addonName, ns = ...

-- "What's new" popup, shown once after an update. Add an entry at the top for each release.
-- ProfitDB.changelogSeen is the newest version the player has been shown; a fresh install
-- skips the popup and just records it.

ns.Changelog = {
  { "0.3.4", {
    "Craft costs in item tooltips: any item a profession makes shows what it costs to craft, from the " ..
      "cheapest recipe you know, or the cheapest of any (marked \"not known\") if you know none. " ..
      "Hold Shift for the reagents and the profit from selling it on the auction house. " ..
      "/prof tooltip turns this off along with disenchant values.",
  } },
  { "0.3.3", {
    "Where to learn recipes: recipe details now say where a recipe or its pattern drops, which vendor " ..
      "sells it, or which quest gives it, from Zockify's WoW Forever recipe database.",
    "About 250 recipes Profit could only guess were taught by trainers are now confirmed, most with " ..
      "the skill needed to learn them, and recipes that come from drops or quests are no longer listed " ..
      "as trainable.",
    "Updated for client build 70888 and the November hotfixes: Minor Arcane Elixir and Iron Grenade " ..
      "sell for less, Coarse Grinding Stone gives skill-ups to 90, and Tanning Rack is learned at 125.",
  } },
  { "0.3.2", {
    "Updated for the live release of WoW Forever (build 70790): recipe skill levels and colors, " ..
      "tools and items now match the live game.",
    "The minimap button now uses the standard LibDBIcon library, so minimap button collectors " ..
      "(and the addon compartment, where there is one) can tidy it away like other addons' buttons. " ..
      "It keeps its place on the minimap.",
  } },
  { "0.3.1", {
    "Vendor flips: a new \"Sell\" choice next to the profession filter. \"Sell: Vendor\" ranks crafts by " ..
      "what a vendor pays for them instead of the auction house, and \"Sell: Highest\" uses whichever pays " ..
      "more, marking prices from a vendor with \"(vendor)\".",
    "Materials you can make yourself are priced at their crafting cost when that's cheaper than buying " ..
      "them, e.g. Bolts of Woolen Cloth from Wool Cloth. Recipe details show what they're crafted from.",
    "Favorites: point at a recipe and click the star on its left (or right-click the recipe), then pick " ..
      "\"Favorites\" in the filter to see just those. Favorites are saved per character.",
  } },
  { "0.3.0", {
    "Disenchanting! Item tooltips show the estimated disenchant value of weapons and armor, based on " ..
      "Auctionator prices for the materials. Hold Shift to see each material with its chance and price. " ..
      "Turn it off with /prof tooltip.",
    "Enchanters get a \"Disenchant from AH\" choice in the filter: gear on the auction house worth more " ..
      "disenchanted than it costs, from your last Auctionator scan, leaving out items above your " ..
      "Enchanting skill. Click an item with the auction house open to search for it.",
    "New Disenchant column: the profit from crafting an item to disenchant instead of selling it.",
    "Recipe details list what crafted gear disenchants into, and say when disenchanting beats selling.",
    "Profit records what your disenchants give. If one gives something Profit didn't expect, it asks " ..
      "you to share your /prof export so the data can be fixed. /prof testdisenchant shows that popup " ..
      "after your next disenchant, to try it.",
    "The Profit column fits its numbers, leaving more room for recipe names, and its header no longer " ..
      "runs into the next one.",
    "/prof debug opens a window you can copy from, and includes the addon version.",
    "More vendor items recorded, including several fish and patterns. Data updated for client build 70245.",
  } },
  { "0.2.3", {
    "New \"Known + trainable\" filter: recipes you know plus ones a trainer teaches at your skill, " ..
      "leaving out recipes only learned from patterns.",
    "This window: what's new in each update. Reopen it with /prof changelog.",
    "Trainer skill levels for 32 Blacksmithing and 12 Mining recipes.",
    "A few more vendor items (Thunder Ale, Rhapsody Malt and some patterns) are priced at the vendor.",
  } },
  { "0.2.2", {
    "/prof debug shows which game features Profit can use on your client; include it in bug reports.",
    "Recipe and item data updated for client build 70170.",
  } },
  { "0.2.1", {
    "Trainer skill levels for 25 Tailoring recipes, from a player's recordings.",
  } },
  { "0.2.0", {
    "Dropdowns for the filter and profession, with a \"Main professions\" choice.",
    "The window opens on Known only, with the Profit column first.",
    "The Skill column shows whether a recipe comes from a trainer, a pattern or both.",
    "Prices use gold, silver and copper icons.",
  } },
}

local window

local function Text(entries)
  local lines = {}
  for _, entry in ipairs(entries) do
    if #lines > 0 then table.insert(lines, " ") end
    table.insert(lines, "|cffffd100Version " .. entry[1] .. "|r")
    for _, change in ipairs(entry[2]) do table.insert(lines, "- " .. change) end
  end
  return table.concat(lines, "\n")
end

local function Create()
  local f = CreateFrame("Frame", "ProfitChangelogWindow", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 300)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  table.insert(UISpecialFrames, "ProfitChangelogWindow") -- close with Escape
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("Profit: what's new")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -32)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(370, 1)
  scroll:SetScrollChild(content)
  f.text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetPoint("TOPLEFT")
  f.text:SetWidth(370)
  f.text:SetJustifyH("LEFT")
  f.text:SetSpacing(3)
  f.content = content

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(100, 22)
  close:SetPoint("BOTTOM", 0, 14)
  close:SetText("Got it")
  close:SetScript("OnClick", function() f:Hide() end)
  window = f
end

-- Show the given entries (default: all of them).
function ns.ShowChangelog(entries)
  if not window then Create() end
  window.text:SetText(Text(entries or ns.Changelog))
  window.content:SetHeight(window.text:GetStringHeight() + 4)
  window:Show()
  ProfitDB.changelogSeen = ns.Changelog[1][1]
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  local seen = ProfitDB.changelogSeen
  if ns.FreshInstall then
    ProfitDB.changelogSeen = ns.Changelog[1][1]
    return
  end
  -- Entries newer than the last one shown; players from before the popup existed get the newest.
  local unseen = {}
  for _, entry in ipairs(ns.Changelog) do
    if entry[1] == seen then break end
    table.insert(unseen, entry)
  end
  if not seen then unseen = { ns.Changelog[1] } end
  if #unseen > 0 then
    C_Timer.After(3, function() ns.ShowChangelog(unseen) end) -- after the login screen settles
  end
end)
