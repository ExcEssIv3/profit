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
-- ProfessionsDB (see Record.lua) adds trainer skills and merchant items seen since the data was built.

local AH_CUT = 0.05 -- faction auction house; neutral auction houses aren't supported

ns.ProfessionNames = {}
for _, recipe in pairs(ns.Recipes) do ns.ProfessionNames[recipe.p] = true end

local function AuctionPrice(itemID)
  local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, addonName, itemID)
  return ok and price or nil
end

local function Recorded(section, key)
  return ProfessionsDB and ProfessionsDB[section] and ProfessionsDB[section][key]
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

local function ItemName(itemID)
  local item = ns.Items[itemID]
  return item and item.n or ("item:" .. itemID)
end

local function FormatMoney(copper)
  if not copper then return "no price" end
  local sign = copper < 0 and "-" or ""
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return string.format("%s%dg %ds %dc", sign, g, s, c) end
  if s > 0 then return string.format("%s%ds %dc", sign, s, c) end
  return string.format("%s%dc", sign, c)
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
  end
  return result
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

local function PrintBreakdown(spellID)
  local e = ns.Evaluate(spellID)
  local r = e.recipe
  print(string.format("|cffffd100%s|r (%s)", r.n, r.p))
  -- Where to learn it only matters if this character doesn't know it yet.
  local sources = ns.IsKnown(spellID) and {} or ns.Sources(spellID)
  if #sources == 0 then print("  Known") end
  for _, source in ipairs(sources) do
    if source == "trainer" then
      print(string.format("  Trainer: learn at skill %d", TrainerSkill(spellID)))
    elseif source == "trainer_inferred" then
      print("  Probably a trainer: learn level unknown (visit a trainer to record it)")
    elseif source == "unknown" then
      print("  Source unknown; the game data looks incomplete, so it may not be obtainable")
    elseif source == "item" then
      for i = 1, #r.ri, 2 do
        local itemID, supply = r.ri[i], ns.VendorSupply(r.ri[i])
        local where = supply == "unlimited" and ("vendor " .. FormatMoney(ns.Items[itemID].b))
          or supply == "limited" and ("vendor (limited) " .. FormatMoney(ns.Items[itemID].b))
          or ("auction " .. FormatMoney(AuctionPrice(itemID)))
        print(string.format("  %s: learn at skill %d, %s", ItemName(itemID), r.ri[i + 1], where))
      end
    end
  end
  for _, reagent in ipairs(e.reagents) do
    print(string.format("  %dx %s: %s%s", reagent.count, ItemName(reagent.itemID),
      reagent.price and FormatMoney(reagent.price * reagent.count) or "no price",
      reagent.priceSource == "vendor" and " (vendor)" or ""))
  end
  print("  Cost: " .. FormatMoney(e.cost))
  if r.m then
    print(string.format("  Sells for (after %d%% cut): %s  |  vendor: %s%s", AH_CUT * 100,
      FormatMoney(e.revenue), FormatMoney(e.vendorValue), e.belowVendor and "  |cffff4040(vendor it instead)|r" or ""))
    print("  Profit: " .. FormatMoney(e.profit))
  else
    print("  Makes no item (e.g. an enchant); not priced.")
  end
  if r.x then print("  |cffff4040Data issue: " .. table.concat(r.x, ", ") .. "|r") end
end

local function PrintTop(limit, profession)
  local rows = {}
  for spellID, recipe in pairs(ns.Recipes) do
    if recipe.m and not recipe.x and (not profession or recipe.p:lower() == profession) then
      local e = ns.Evaluate(spellID)
      if e.profit then table.insert(rows, e) end
    end
  end
  table.sort(rows, function(a, b) return a.profit > b.profit end)
  print(string.format("|cffffd100Top %d crafts%s|r (%d fully priced)", limit,
    profession and (" for " .. profession) or "", #rows))
  for i = 1, math.min(limit, #rows) do
    local e = rows[i]
    print(string.format("%2d. %s (%s): %s%s", i, e.recipe.n, e.recipe.p, FormatMoney(e.profit),
      e.belowVendor and "  |cffff4040(vendor)|r" or ""))
  end
end

SLASH_PROFESSIONS1 = "/professions"
SLASH_PROFESSIONS2 = "/prof"
SlashCmdList.PROFESSIONS = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "help" then
    print("/prof top [count] [profession] - most profitable crafts with full price data")
    print("/prof <recipe name> - cost and profit breakdown for one recipe")
  elseif cmd == "top" then
    local count, profession = rest:match("^(%d*)%s*(.-)$")
    PrintTop(tonumber(count) or 10, profession ~= "" and profession:lower() or nil)
  else
    local spellID = FindRecipe(msg)
    if spellID then PrintBreakdown(spellID) else print("No recipe matching \"" .. msg .. "\"") end
  end
end

-- Placeholder for the UI: recompute when Auctionator's prices change (e.g. after a scan).
function ns.OnPricesUpdated() end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  if Auctionator.API.v1.RegisterForDBUpdate then
    Auctionator.API.v1.RegisterForDBUpdate(addonName, function() ns.OnPricesUpdated() end)
  end
end)
