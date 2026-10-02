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
-- ProfitDB (see Record.lua) adds trainer skills and merchant items seen since the data was built.

local AH_CUT = 0.05 -- faction auction house; neutral auction houses aren't supported

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
      table.insert(rows, e)
    end
  end
  return rows
end

-- Sort helper: rows missing the sort value go last.
function ns.SortRows(rows, key, ascending)
  table.sort(rows, function(a, b)
    local x, y = a[key], b[key]
    if x == nil or y == nil then
      if x == y then return a.recipe.n < b.recipe.n end
      return y == nil
    end
    if x == y then return a.recipe.n < b.recipe.n end
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

local function PrintDebug()
  local version, build, _, interface = GetBuildInfo()
  print(string.format("|cffffd100Profit debug|r: client %s.%s, interface %s, data build %s",
    version, build, tostring(interface), ns.DataBuild or "?"))
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
      print(string.format("  %s: |cff40c040%s|r", feature[1], using))
    else
      print(string.format("  %s: %s%s|r", feature[1], feature.optional and "|cff808080not available, " or
        "|cffff4040MISSING, ", table.concat(missing, "; ")))
    end
  end
  local professions, known = {}, 0
  for name, skill in pairs(ProfitCharDB.skills) do table.insert(professions, name .. " " .. skill) end
  for _, recipes in pairs(ProfitCharDB.known) do for _ in pairs(recipes) do known = known + 1 end end
  local trainer, merchant = 0, 0
  for _ in pairs(ProfitDB.trainer) do trainer = trainer + 1 end
  for _ in pairs(ProfitDB.merchant) do merchant = merchant + 1 end
  table.sort(professions)
  print(string.format("  Character: %s; %d known recipes", #professions > 0 and table.concat(professions, ", ")
    or "no professions detected", known))
  print(string.format("  Recorded: %d trainer recipes, %d merchant items", trainer, merchant))
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
    print("/prof debug - which game APIs Profit uses on this client")
    print("/prof <recipe name> - cost and profit breakdown for one recipe")
  elseif cmd == "top" then
    local count, profession = rest:match("^(%d*)%s*(.-)$")
    local name = ProfessionName(profession)
    if name == false then print("Unknown profession \"" .. profession .. "\"") return end
    PrintTop(tonumber(count) or 10, name)
  elseif cmd == "export" then
    if ns.ShowExport then ns.ShowExport() end
  elseif cmd == "debug" then
    PrintDebug()
  elseif cmd == "minimap" then
    if ns.ToggleMinimapButton then ns.ToggleMinimapButton() end
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
frame:SetScript("OnEvent", function()
  if Auctionator.API.v1.RegisterForDBUpdate then
    Auctionator.API.v1.RegisterForDBUpdate(addonName, function() ns.Refresh() end)
  end
end)
