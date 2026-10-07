local addonName, ns = ...

-- Data/Recipes.lua, keyed by recipe spell ID:
--   n name, p profession, s {source, ...}: every way to learn it, from "trainer" (including recipes
--     learned automatically, at skill 1) and "item", or on its own "trainer_inferred" (no recipe
--     item, so probably a trainer) or "unknown"
--   m {itemID, count} made (nil for enchants), r {itemID, count, itemID, count, ...} reagents
--   l learn skill, t trainer's learn skill, y yellow, g grey (any may be nil)
--   ri {itemID, learnSkill, ...} recipe items
--   x {issue, ...} data problems; such recipes are likely not obtainable
-- Data/Items.lua, keyed by item ID: n name, q quality, b vendor buy price, v vendor sell price (copper),
--   vs sold by vendors in unlimited supply, vl sold by vendors in limited supply
-- Data/Disenchant.lua, keyed by disenchant bracket: c item class, q quality, lo..hi item level,
--   s Enchanting skill needed (nil if unknown),
--   r {itemID, chance %, min, max, ...} results (from tools/disenchant.py), i {itemID, ...} items in
--   the client data that disenchant this way; ns.NoDisenchant {itemID, ...} gear that can't be
-- ProfitDB (see Record.lua) adds trainer skills and merchant items seen since the data was built.

local AH_CUT = 0.05 -- faction auction house; neutral auction houses aren't supported

local DisenchantBracket = {} -- itemID -> bracket, or false if it can't be disenchanted
for bracket, de in pairs(ns.Disenchant) do
  for _, itemID in ipairs(de.i) do DisenchantBracket[itemID] = bracket end
end
for _, itemID in ipairs(ns.NoDisenchant) do DisenchantBracket[itemID] = false end

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local ITEM_CLASS_WEAPON, ITEM_CLASS_ARMOR = 2, 4
-- The client data lacks many items (the server sends them), so match those by what the game
-- reports about them, and remember the answer. nil until the item is cached; the second value is
-- true in that case.
local function FindBracket(itemID)
  local known = DisenchantBracket[itemID]
  if known ~= nil then return known or nil end
  -- Only gear disenchants. The item class is in the client, so this needs no server request.
  local okInstant, _, _, _, _, _, instantClass = pcall(GetItemInfoInstant, itemID)
  if okInstant and instantClass and instantClass ~= ITEM_CLASS_WEAPON and instantClass ~= ITEM_CLASS_ARMOR then
    DisenchantBracket[itemID] = false
    return nil
  end
  local ok, _, _, quality, level, _, _, _, _, _, _, _, class = pcall(GetItemInfo, itemID)
  if not (ok and quality and level and class) then return nil, true end
  DisenchantBracket[itemID] = false
  for bracket, de in pairs(ns.Disenchant) do
    if de.c == class and de.q == quality and level >= de.lo and level <= de.hi then
      DisenchantBracket[itemID] = bracket
      return bracket
    end
  end
end

-- Enchanting skill needed to disenchant the item, or nil if unknown or not disenchantable.
function ns.DisenchantSkill(itemID)
  local bracket = FindBracket(itemID)
  return bracket and ns.Disenchant[bracket].s
end

ns.ProfessionNames = {}
for _, recipe in pairs(ns.Recipes) do ns.ProfessionNames[recipe.p] = true end
ns.SecondaryProfessions = { Cooking = true, ["First Aid"] = true, Fishing = true }

-- This character's primary professions, as a set, e.g. { Tailoring = true, Enchanting = true }.
function ns.MainProfessions()
  local set = {}
  for name in pairs(ns.ProfessionNames) do
    if ns.SkillLevel(name) and not ns.SecondaryProfessions[name] then set[name] = true end
  end
  return set
end

local function AuctionPrice(itemID)
  local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, addonName, itemID)
  return ok and price or nil
end

local function Recorded(section, key)
  return ProfitDB and ProfitDB[section] and ProfitDB[section][key]
end

-- "unlimited", "limited" or nil.
function ns.VendorSupply(itemID)
  local item, seen = ns.Items[itemID], Recorded("merchant", itemID)
  if (item and item.vs) or (seen and not seen.limited) then return "unlimited" end
  if (item and item.vl) or seen then return "limited" end
end

-- Vendor materials cost their list price everywhere (reputation discounts aside); everything
-- else is priced from the auction house. Returns price, "vendor" | "auction".
local function ReagentPrice(itemID)
  if ns.VendorSupply(itemID) == "unlimited" then
    local item, seen = ns.Items[itemID], Recorded("merchant", itemID)
    return (item and item.b > 0 and item.b) or (seen and seen.price), "vendor"
  end
  return AuctionPrice(itemID), "auction"
end

-- Lowest skill the recipe can be learned at, or nil if no trainer visit has recorded it.
function ns.LearnSkill(spellID)
  local recipe, seen = ns.Recipes[spellID], Recorded("trainer", spellID)
  if seen and (not recipe.l or seen.skill < recipe.l) then return seen.skill end
  return recipe.l
end

-- Every way to learn the recipe, adding "trainer" once a trainer has been seen teaching it.
function ns.Sources(spellID)
  local recipe = ns.Recipes[spellID]
  local sources, hasTrainer = {}, false
  for _, source in ipairs(recipe.s) do
    if source == "trainer" then hasTrainer = true end
    table.insert(sources, source)
  end
  if not hasTrainer and Recorded("trainer", spellID) then
    if sources[1] == "trainer_inferred" or sources[1] == "unknown" then sources = {} end
    table.insert(sources, "trainer")
  end
  return sources
end

local function TrainerSkill(spellID)
  local seen = Recorded("trainer", spellID)
  return seen and seen.skill or ns.Recipes[spellID].t
end

function ns.ItemName(itemID)
  local item = ns.Items[itemID]
  return item and item.n or ("item:" .. itemID)
end
local ItemName = ns.ItemName

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function ns.FormatMoney(copper)
  if not copper then return "no price" end
  local sign = copper < 0 and "-" or ""
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return string.format("%s%d%s %d%s %d%s", sign, g, GOLD, s, SILVER, c, COPPER) end
  if s > 0 then return string.format("%s%d%s %d%s", sign, s, SILVER, c, COPPER) end
  return string.format("%s%d%s", sign, c, COPPER)
end
local FormatMoney = ns.FormatMoney

-- Expected auction value (after the cut) of disenchanting one item. Returns value or nil if any
-- result has no price, the results as { itemID, chance, min, max, price }, and the unpriced item IDs.
-- Returns nil if the item can't be disenchanted.
function ns.DisenchantValue(itemID)
  local bracket = FindBracket(itemID)
  if not bracket then return nil end
  local results = ns.Disenchant[bracket].r
  local value, outcomes, missing = 0, {}, {}
  for i = 1, #results, 4 do
    local matID, chance, low, high = results[i], results[i + 1], results[i + 2], results[i + 3]
    local price = AuctionPrice(matID)
    table.insert(outcomes, { itemID = matID, chance = chance, min = low, max = high, price = price })
    if price then
      value = value + chance / 100 * (low + high) / 2 * price * (1 - AH_CUT)
    else
      table.insert(missing, matID)
    end
  end
  return #missing == 0 and value or nil, outcomes, missing
end

-- Price out one recipe. Any field that depends on a missing price is nil, and the
-- item IDs without prices are listed in `missing`.
function ns.Evaluate(spellID)
  local recipe = ns.Recipes[spellID]
  if not recipe then return nil end
  local result = { spellID = spellID, recipe = recipe, missing = {}, reagents = {} }

  local cost = 0
  for i = 1, #recipe.r, 2 do
    local itemID, count = recipe.r[i], recipe.r[i + 1]
    local price, priceSource = ReagentPrice(itemID)
    table.insert(result.reagents, { itemID = itemID, count = count, price = price, priceSource = priceSource })
    if not price then
      table.insert(result.missing, itemID)
    elseif cost then
      cost = cost + price * count
    end
  end
  if #result.missing > 0 then cost = nil end
  result.cost = cost

  if recipe.m then
    local itemID, count = recipe.m[1], recipe.m[2]
    local price = AuctionPrice(itemID)
    local item = ns.Items[itemID]
    result.vendorValue = item and item.v * count or nil
    if price then
      result.revenue = price * count * (1 - AH_CUT)
      -- Selling to a vendor pays more than the auction house would.
      result.belowVendor = result.vendorValue ~= nil and result.revenue < result.vendorValue
    else
      table.insert(result.missing, itemID)
    end
    if result.revenue and result.cost then
      result.profit = result.revenue - result.cost
    end
    -- Crafting to disenchant: each made item is disenchanted separately.
    local deValue, outcomes = ns.DisenchantValue(itemID)
    result.disenchant = outcomes
    if deValue then
      result.deValue = deValue * count
      if result.cost then result.deProfit = result.deValue - result.cost end
    end
  end
  return result
end

-- Skill color of a recipe at this character's current skill: "red" (can't learn yet), "orange",
-- "yellow", "green", "grey", or nil when the skill or the recipe's ranges aren't known.
ns.ColorCodes = { red = "ffff4040", orange = "ffff8040", yellow = "ffffff00", green = "ff40c040", grey = "ff808080" }
function ns.Color(spellID)
  local recipe = ns.Recipes[spellID]
  local skill = ns.SkillLevel(recipe.p)
  if not skill then return nil end
  local learn = ns.LearnSkill(spellID)
  if learn and skill < learn and not ns.IsKnown(spellID) then return "red" end
  local yellow, grey = recipe.y, recipe.g
  if not (yellow and grey) then return nil end
  if skill < yellow then return "orange" end
  if skill < (yellow + grey) / 2 then return "yellow" end
  if skill < grey then return "green" end
  return "grey"
end

-- Can this character learn it now? true, false, or nil when the learn level isn't recorded.
function ns.CanLearn(spellID)
  local skill, learn = ns.SkillLevel(ns.Recipes[spellID].p), ns.LearnSkill(spellID)
  if not (skill and learn) then return nil end
  return skill >= learn
end

-- A trainer teaches it and this character's skill is high enough (or the trainer's level isn't
-- recorded). The trainer's level, not the lowest learn level: a pattern may need less skill.
local function TrainableNow(spellID)
  local skill = ns.SkillLevel(ns.Recipes[spellID].p)
  if not skill then return false end
  for _, source in ipairs(ns.Sources(spellID)) do
    if source == "trainer" then
      local trainer = TrainerSkill(spellID)
      return not trainer or skill >= trainer
    end
    if source == "trainer_inferred" then return true end
  end
  return false
end

-- Recipes to rank, each with its evaluation. Filters:
--   "mine"  (default) this character's professions: known recipes plus ones learnable now,
--           including ones whose learn level hasn't been recorded (learnable = nil)
--   "known" known recipes only
--   "trainable" known recipes plus ones a trainer teaches at the character's skill, including
--           probable trainer recipes ("trainer_inferred"); leaves out pattern-only recipes
--   "all"   every recipe
-- `profession` is one profession's name, a set of names (see ns.MainProfessions), or nil for all.
-- Recipes that make no item (enchants) or look unobtainable (data issues) are left out.
-- Grey recipes are kept: they can still be profitable.
function ns.Rank(filter, profession, search)
  filter = filter or "mine"
  search = search and search ~= "" and search:lower() or nil
  local rows = {}
  for spellID, recipe in pairs(ns.Recipes) do
    local include = recipe.m and not recipe.x
      and (not profession or recipe.p == profession or (type(profession) == "table" and profession[recipe.p]))
      and (not search or recipe.n:lower():find(search, 1, true))
    if include and filter ~= "all" then
      local known = ns.IsKnown(spellID)
      if filter == "known" then
        include = known
      elseif filter == "trainable" then
        include = known or TrainableNow(spellID)
      else
        include = ns.SkillLevel(recipe.p) ~= nil and (known or ns.CanLearn(spellID) ~= false)
      end
    end
    if include then
      local e = ns.Evaluate(spellID)
      e.known, e.canLearn, e.color = ns.IsKnown(spellID), ns.CanLearn(spellID), ns.Color(spellID)
      e.key, e.name = spellID, recipe.n
      table.insert(rows, e)
    end
  end
  return rows
end

-- Item IDs Auctionator has prices for. Reads its price database, which isn't part of its API,
-- so fall back to every item in our data if that changes. Second value: true if from Auctionator.
local function PricedItemIDs()
  local ok, db = pcall(function() return Auctionator.Database.db end)
  if ok and type(db) == "table" then
    local ids = {}
    for key in pairs(db) do
      local id = type(key) == "string" and tonumber(key:match("^(%d+)$"))
      if id then table.insert(ids, id) end
    end
    return ids, true
  end
  local ids = {}
  for _, de in pairs(ns.Disenchant) do
    for _, itemID in ipairs(de.i) do table.insert(ids, itemID) end
  end
  return ids, false
end

-- Items not loaded yet are requested once; GET_ITEM_INFO_RECEIVED refreshes the window.
local requested = {}
local function RequestItem(itemID)
  if requested[itemID] or not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  requested[itemID] = true
  pcall(C_Item.RequestLoadItemDataByID, itemID)
end

function ns.ItemDisplayName(itemID)
  local ok, name = pcall(GetItemInfo, itemID)
  return ok and name or ns.ItemName(itemID)
end

-- Gear on the auction house worth more disenchanted than it costs, for an enchanter. Each row:
-- { key, itemID, name, cost (auction price), deValue, profit, skill }. Leaves out items needing
-- more Enchanting skill than the character has; their count is the second value.
function ns.DisenchantDeals(search)
  search = search and search ~= "" and search:lower() or nil
  local enchanting = ns.SkillLevel("Enchanting") or 0
  local rows, tooHigh = {}, 0
  for _, itemID in ipairs((PricedItemIDs())) do
    local bracket, loading = FindBracket(itemID)
    if loading then RequestItem(itemID) end
    local price = bracket and AuctionPrice(itemID)
    local deValue = price and ns.DisenchantValue(itemID)
    if deValue and deValue > price then
      local skill = ns.Disenchant[bracket].s
      local name = ns.ItemDisplayName(itemID)
      if skill and skill > enchanting then
        tooHigh = tooHigh + 1
      elseif not search or name:lower():find(search, 1, true) then
        table.insert(rows, { key = "item:" .. itemID, itemID = itemID, name = name, cost = price, deValue = deValue,
          profit = deValue - price, skill = skill })
      end
    end
  end
  return rows, tooHigh
end

-- Breakdown of buying one item to disenchant, as display lines.
function ns.DisenchantLines(itemID)
  local lines = {}
  local function add(fmt, ...) table.insert(lines, string.format(fmt, ...)) end
  local price, skill = AuctionPrice(itemID), ns.DisenchantSkill(itemID)
  local value, outcomes = ns.DisenchantValue(itemID)
  add("|cffffd100%s|r", ns.ItemDisplayName(itemID))
  add("Enchanting skill to disenchant: %s", skill or "unknown")
  add("Auction price: %s", FormatMoney(price))
  add(" ")
  add("Disenchants into:")
  for _, o in ipairs(outcomes or {}) do
    add("  %s%% %sx %s: %s each", o.chance, o.min == o.max and o.min or (o.min .. "-" .. o.max),
      ItemName(o.itemID), FormatMoney(o.price))
  end
  add("Disenchant value (after cut): %s", FormatMoney(value))
  add("Profit: %s", FormatMoney(value and price and value - price))
  add(" ")
  add("Click the item with the auction house open to search for it.")
  return lines
end

-- Sort helper: rows missing the sort value go last.
function ns.SortRows(rows, key, ascending)
  table.sort(rows, function(a, b)
    local x, y = a[key], b[key]
    if x == nil or y == nil then
      if x == y then return a.name < b.name end
      return y == nil
    end
    if x == y then return a.name < b.name end
    if ascending then return x < y end
    return x > y
  end)
end

-- Breakdown of one recipe as display lines, shared by chat and the window.
function ns.BreakdownLines(spellID)
  local e = ns.Evaluate(spellID)
  local r = e.recipe
  local lines = {}
  local function add(fmt, ...) table.insert(lines, string.format(fmt, ...)) end

  local color, skill = ns.Color(spellID), ns.SkillLevel(r.p)
  add("|cffffd100%s|r (%s)", r.n, r.p)
  add("Skill: yellow %s, grey %s%s", r.y or "?", r.g or "?",
    color and string.format(" (|c%s%s|r at your %d)", ns.ColorCodes[color], color, skill) or "")

  -- Where to learn it only matters if this character doesn't know it yet.
  local sources = ns.IsKnown(spellID) and {} or ns.Sources(spellID)
  if #sources == 0 then add("Known") end
  for _, source in ipairs(sources) do
    if source == "trainer" then
      add("Trainer: learn at skill %d", TrainerSkill(spellID))
    elseif source == "trainer_inferred" then
      add("Probably a trainer: learn level unknown (visit a trainer to record it)")
    elseif source == "unknown" then
      add("Source unknown; the game data looks incomplete, so it may not be obtainable")
    elseif source == "item" then
      for i = 1, #r.ri, 2 do
        local itemID, supply = r.ri[i], ns.VendorSupply(r.ri[i])
        local where = supply == "unlimited" and ("vendor " .. FormatMoney(ns.Items[itemID].b))
          or supply == "limited" and ("vendor (limited) " .. FormatMoney(ns.Items[itemID].b))
          or ("auction " .. FormatMoney(AuctionPrice(itemID)))
        add("%s: learn at skill %d, %s", ItemName(itemID), r.ri[i + 1], where)
      end
    end
  end

  add(" ")
  for _, reagent in ipairs(e.reagents) do
    add("%dx %s: %s%s", reagent.count, ItemName(reagent.itemID),
      reagent.price and FormatMoney(reagent.price * reagent.count) or "no price",
      reagent.priceSource == "vendor" and " (vendor)" or "")
  end
  add("Cost: %s", FormatMoney(e.cost))
  if r.m then
    add("Sells for (after %d%% cut): %s", AH_CUT * 100, FormatMoney(e.revenue))
    add("Vendor value: %s%s", FormatMoney(e.vendorValue), e.belowVendor and "  |cffff4040(vendor it instead)|r" or "")
    add("Profit: %s", FormatMoney(e.profit))
    if e.disenchant then
      add(" ")
      add("Disenchants into%s:", r.m[2] > 1 and string.format(" (each of %d)", r.m[2]) or "")
      for _, o in ipairs(e.disenchant) do
        add("  %s%% %s%s: %s each", o.chance, o.min == o.max and o.min or (o.min .. "-" .. o.max),
          "x " .. ItemName(o.itemID), FormatMoney(o.price))
      end
      add("Disenchant value (after cut): %s", FormatMoney(e.deValue))
      add("Disenchant profit: %s%s", FormatMoney(e.deProfit),
        e.deProfit and e.profit and e.deProfit > e.profit and "  |cff40c040(better than selling)|r" or "")
    end
  else
    add("Makes no item (e.g. an enchant); not priced.")
  end
  if r.x then add("|cffff4040Data issue: %s|r", table.concat(r.x, ", ")) end
  return lines
end

local function FindRecipe(query)
  query = query:lower()
  local partial
  for spellID, recipe in pairs(ns.Recipes) do
    local name = recipe.n:lower()
    if name == query then return spellID end
    if not partial and name:find(query, 1, true) then partial = spellID end
  end
  return partial
end

local function PrintTop(limit, profession)
  local filter = "mine"
  local hasSkills = false
  for name in pairs(ns.ProfessionNames) do if ns.SkillLevel(name) then hasSkills = true end end
  if not hasSkills then filter = "all" end
  local rows = {}
  for _, e in ipairs(ns.Rank(filter, profession)) do
    if e.profit then table.insert(rows, e) end
  end
  ns.SortRows(rows, "profit")
  print(string.format("|cffffd100Top %d crafts%s|r (%d fully priced%s)", limit,
    profession and (" for " .. profession) or "", #rows,
    filter == "all" and "; no professions detected, showing all recipes" or ", known or learnable"))
  for i = 1, math.min(limit, #rows) do
    local e = rows[i]
    local color = e.color and ("|c" .. ns.ColorCodes[e.color]) or ""
    print(string.format("%2d. %s%s|r (%s): %s%s%s", i, color, e.recipe.n, e.recipe.p, FormatMoney(e.profit),
      e.known and "" or "  (not learned)", e.belowVendor and "  |cffff4040(vendor)|r" or ""))
  end
end

-- Case-insensitive profession name match, e.g. "leatherworking" -> "Leatherworking".
local function ProfessionName(text)
  if text == "" then return nil end
  for name in pairs(ns.ProfessionNames) do
    if name:lower() == text:lower() then return name end
  end
  return false
end

-- /prof debug: which game API each feature uses on this client. Each feature lists alternatives
-- in the order the code tries them, as { name, function, ... }; the first whose functions all
-- exist is in use. Keep in step with the code when adding or changing an API call.
local API_FEATURES = {
  { "Prices", { "Auctionator", "Auctionator.API.v1.GetAuctionPriceByItemID" } },
  { "Price updates", { "Auctionator", "Auctionator.API.v1.RegisterForDBUpdate" }, optional = true },
  { "Skill levels", { "skill list", "GetNumSkillLines", "GetSkillLineInfo" },
    { "professions", "GetProfessions", "GetProfessionInfo" } },
  { "Known recipes", { "C_TradeSkillUI", "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo" },
    { "Classic trade skills", "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo" } },
  { "Known recipes (craft window)", { "Classic crafts", "GetCraftDisplaySkillLine", "GetNumCrafts", "GetCraftInfo" },
    optional = true },
  { "Open recipe", { "C_TradeSkillUI", "C_TradeSkillUI.OpenRecipe" },
    { "select in open Classic window", "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo" } },
  { "Trainer recording", { "trainer services", "GetNumTrainerServices", "GetTrainerServiceInfo",
    "GetTrainerServiceSkillReq" } },
  { "Trainer filters", { "trainer filters", "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter" },
    optional = true },
  { "Merchant recording", { "C_MerchantFrame", "C_MerchantFrame.GetItemInfo", "GetMerchantNumItems", "GetMerchantItemID" },
    { "Classic merchant", "GetMerchantItemInfo", "GetMerchantNumItems", "GetMerchantItemID" } },
  { "Disenchant (items not in data)", { "C_Item", "C_Item.GetItemInfo" }, { "GetItemInfo", "GetItemInfo" } },
  { "Disenchant recording", { "loot source", "GetLootSourceInfo", "C_Item.GetItemIDByGUID", "GetNumLootItems",
    "GetLootSlotLink", "GetLootSlotInfo" },
    { "bag click", "C_Container.UseContainerItem", "C_Container.GetContainerItemID", "SpellIsTargeting",
      "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo" },
    { "bag click (old API)", "UseContainerItem", "GetContainerItemID", "SpellIsTargeting", "GetNumLootItems",
      "GetLootSlotLink", "GetLootSlotInfo" } },
  { "Disenchant deals (item list)", { "Auctionator price database", "Auctionator.Database.db" },
    { "Profit's item data", "Auctionator.API.v1.GetAuctionPriceByItemID" } },
  { "Disenchant deals (load items)", { "C_Item", "C_Item.RequestLoadItemDataByID" }, optional = true },
  { "Disenchant (skip non-gear)", { "C_Item", "C_Item.GetItemInfoInstant" }, { "GetItemInfoInstant", "GetItemInfoInstant" },
    optional = true },
  { "Disenchant deals (AH search)", { "Auctionator", "Auctionator.API.v1.MultiSearchExact" }, optional = true },
  { "Item tooltip", { "tooltip data", "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType" },
    { "OnTooltipSetItem", "GameTooltip.HookScript", "GameTooltip.GetItem" } },
  { "Addon version", { "C_AddOns", "C_AddOns.GetAddOnMetadata" }, { "GetAddOnMetadata", "GetAddOnMetadata" },
    optional = true },
  { "Dropdowns", { "menu system", "MenuUtil", "DropdownButtonMixin" },
    { "UIDropDownMenu", "UIDropDownMenu_Initialize", "UIDropDownMenu_SetText" } },
}

local function Exists(path)
  local value = _G
  for key in path:gmatch("[^.]+") do
    if type(value) ~= "table" then return false end
    value = value[key]
  end
  return value ~= nil
end

-- Plain text (no color codes) so it pastes cleanly into a bug report.
local function DebugText()
  local lines = {}
  local function add(fmt, ...) table.insert(lines, string.format(fmt, ...)) end
  local version, build, _, interface = GetBuildInfo()
  local metadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  local addonVersion = metadata and metadata(addonName, "Version")
  -- The packager fills in the version from the release tag; a copy from git still has the placeholder.
  if addonVersion and addonVersion:find("^@") then addonVersion = "dev" end
  add("Profit %s: client %s.%s, interface %s, data build %s", addonVersion or "?", version, build,
    tostring(interface), ns.DataBuild or "?")
  for _, feature in ipairs(API_FEATURES) do
    local using, missing = nil, {}
    for a = 2, #feature do
      local alternative = feature[a]
      local absent = {}
      for i = 2, #alternative do
        if not Exists(alternative[i]) then table.insert(absent, alternative[i]) end
      end
      if #absent == 0 then using = alternative[1] break end
      table.insert(missing, alternative[1] .. " (no " .. table.concat(absent, ", ") .. ")")
    end
    if using then
      add("  %s: %s", feature[1], using)
    else
      add("  %s: %s%s", feature[1], feature.optional and "not available, " or "MISSING, ", table.concat(missing, "; "))
    end
  end
  local professions, known = {}, 0
  for name, skill in pairs(ProfitCharDB.skills) do table.insert(professions, name .. " " .. skill) end
  for _, recipes in pairs(ProfitCharDB.known) do for _ in pairs(recipes) do known = known + 1 end end
  local trainer, merchant, disenchants = 0, 0, 0
  for _ in pairs(ProfitDB.trainer) do trainer = trainer + 1 end
  for _ in pairs(ProfitDB.merchant) do merchant = merchant + 1 end
  for _, d in pairs(ProfitDB.disenchant) do disenchants = disenchants + d.n end
  table.sort(professions)
  add("  Character: %s; %d known recipes", #professions > 0 and table.concat(professions, ", ")
    or "no professions detected", known)
  add("  Recorded: %d trainer recipes, %d merchant items, %d disenchant%s", trainer, merchant, disenchants,
    disenchants == 1 and "" or "s")
  return table.concat(lines, "\n")
end

SLASH_PROFIT1 = "/profit"
SLASH_PROFIT2 = "/prof"
SlashCmdList.PROFIT = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif cmd == "help" then
    print("/prof - open the Profit window")
    print("/prof top [count] [profession] - most profitable known or learnable crafts")
    print("/prof export - copy your trainer and merchant recordings to share")
    print("/prof minimap - show or hide the minimap button")
    print("/prof tooltip - show or hide disenchant values in item tooltips")
    print("/prof debug - which game APIs Profit uses on this client")
    print("/prof testdisenchant - show the \"didn't expect\" popup after your next disenchant")
    print("/prof changelog - what's new in each update")
    print("/prof <recipe name> - cost and profit breakdown for one recipe")
  elseif cmd == "top" then
    local count, profession = rest:match("^(%d*)%s*(.-)$")
    local name = ProfessionName(profession)
    if name == false then print("Unknown profession \"" .. profession .. "\"") return end
    PrintTop(tonumber(count) or 10, name)
  elseif cmd == "export" then
    if ns.ShowExport then ns.ShowExport() end
  elseif cmd == "changelog" then
    if ns.ShowChangelog then ns.ShowChangelog() end
  elseif cmd == "testdisenchant" then
    if ns.TestNextDisenchant then ns.TestNextDisenchant() end
  elseif cmd == "debug" then
    if ns.ShowText then
      ns.ShowText("Profit: debug info", "Press Ctrl+C (Cmd+C on Mac) to copy, then paste it into your bug report " ..
        "at github.com/ExcEssIv3/profit/issues.", DebugText())
    else
      print(DebugText())
    end
  elseif cmd == "minimap" then
    if ns.ToggleMinimapButton then ns.ToggleMinimapButton() end
  elseif cmd == "tooltip" then
    if ns.ToggleTooltip then ns.ToggleTooltip() end
  else
    local spellID = FindRecipe(msg)
    if not spellID then print("No recipe matching \"" .. msg .. "\"") return end
    for i, line in ipairs(ns.BreakdownLines(spellID)) do
      if line ~= " " then print((i == 1 and "" or "  ") .. line) end
    end
  end
end

-- Called when prices, recordings or known recipes change; the window replaces it.
function ns.Refresh() end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event, itemID)
  if event == "GET_ITEM_INFO_RECEIVED" then
    if requested[itemID] then ns.Refresh() end
    return
  end
  if Auctionator.API.v1.RegisterForDBUpdate then
    Auctionator.API.v1.RegisterForDBUpdate(addonName, function() ns.Refresh() end)
  end
end)
