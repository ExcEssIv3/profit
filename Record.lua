local addonName, ns = ...

-- Records what the client data can't tell us, into ProfitDB (account-wide):
--   trainer[spellID]  = { skill, prof, cost, seen, build }  skill needed to learn a trainer recipe
--   merchant[itemID]  = { price, qty, limited, seen, build } items merchants sell for gold
--   disenchant[itemID] = { q quality, il item level, c item class, n times disenchanted, seen, build,
--     r = { [matID] = { n times it dropped, total count, min, max, flagged } } } disenchant results
-- tools/import_recorded.py merges these into the shipped data.

local function Build()
  return tonumber((select(2, GetBuildInfo())))
end

local function ItemIDFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- Trainer services only carry a name and a crafted item link, so match them to recipes of
-- the trainer's profession by the item they make, then by name.
local recipesByProfession
local function MatchRecipes(profession, name, itemID)
  if not recipesByProfession then
    recipesByProfession = {}
    for spellID, recipe in pairs(ns.Recipes) do
      local list = recipesByProfession[recipe.p] or {}
      recipesByProfession[recipe.p] = list
      table.insert(list, spellID)
    end
  end
  local byItem, byName = {}, {}
  for _, spellID in ipairs(recipesByProfession[profession] or {}) do
    local recipe = ns.Recipes[spellID]
    if itemID and recipe.m and recipe.m[1] == itemID then table.insert(byItem, spellID) end
    if recipe.n == name then table.insert(byName, spellID) end
  end
  return #byItem > 0 and byItem or byName
end

-- Show every service (available, unavailable, already known) while scanning, then put the
-- player's filter back.
local FILTERS = { "available", "unavailable", "used" }
local function WithAllTrainerServices(fn)
  if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return fn() end
  local saved = {}
  for _, f in ipairs(FILTERS) do
    -- Forever's client takes a boolean here; Classic Era took 1/0.
    saved[f] = GetTrainerServiceTypeFilter(f) and true or false
    SetTrainerServiceTypeFilter(f, true)
  end
  if ExpandTrainerSkillLine then ExpandTrainerSkillLine(0) end
  -- Restore the player's filter even if the scan errors.
  local ok, err = pcall(fn)
  for _, f in ipairs(FILTERS) do SetTrainerServiceTypeFilter(f, saved[f]) end
  if not ok then error(err, 0) end
end

local scanningTrainer = false
local function ScanTrainer()
  if scanningTrainer then return end -- changing filters fires TRAINER_UPDATE
  scanningTrainer = true
  local now, build, recorded = time(), Build(), 0
  local ok, err = pcall(WithAllTrainerServices, function()
    -- Services without a skill requirement (e.g. the profession rank itself) still tell us
    -- which profession this trainer teaches.
    local profession
    for i = 1, GetNumTrainerServices() do
      local skillName = GetTrainerServiceSkillReq(i)
      if skillName and ns.ProfessionNames[skillName] then profession = skillName break end
    end
    for i = 1, GetNumTrainerServices() do
      local name, _, category = GetTrainerServiceInfo(i)
      if name and category ~= "header" then
        local skillName, skillLevel = GetTrainerServiceSkillReq(i)
        local prof = (skillName and ns.ProfessionNames[skillName]) and skillName or profession
        local itemID = GetTrainerServiceItemLink and ItemIDFromLink(GetTrainerServiceItemLink(i))
        for _, spellID in ipairs(prof and MatchRecipes(prof, name, itemID) or {}) do
          ProfitDB.trainer[spellID] = {
            skill = skillLevel or 1, prof = prof, cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or nil,
            seen = now, build = build,
          }
          recorded = recorded + 1
        end
      end
    end
  end)
  scanningTrainer = false
  if not ok then error(err, 0) end
  ns.Refresh()
  return recorded
end

local function MerchantItem(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(i)
    if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    return nil
  end
  local _, _, price, qty, numAvailable, _, _, extendedCost = GetMerchantItemInfo(i)
  return price, qty, numAvailable, extendedCost
end

local function ScanMerchant()
  local now, build = time(), Build()
  for i = 1, GetMerchantNumItems() do
    local itemID = GetMerchantItemID(i)
    local price, qty, numAvailable, extendedCost = MerchantItem(i)
    -- Skip items bought with currency or other items, and ones not loaded yet.
    if itemID and price and price > 0 and not extendedCost then
      ProfitDB.merchant[itemID] = {
        price = price / math.max(qty or 1, 1), qty = qty,
        limited = (numAvailable or -1) >= 0 or nil, seen = now, build = build,
      }
    end
  end
  ns.Refresh()
end

ns.ScanTrainer = ScanTrainer

-- Disenchanting: the cast tells us a disenchant happened, the loot window what it gave. The item
-- comes from the loot source where the client has it, else from the bag item clicked while
-- targeting the spell.
local DISENCHANT = 13262
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
local clickedItem, pendingDisenchant -- { itemID, time }

-- Left-clicking a bag item while targeting picks it up; right-clicking (and /use) uses it.
local function OnBagItemClick(bag, slot)
  if SpellIsTargeting and SpellIsTargeting() and GetContainerItemID then
    clickedItem = { itemID = GetContainerItemID(bag, slot), time = GetTime() }
  end
end
for _, name in ipairs({ "UseContainerItem", "PickupContainerItem" }) do
  if C_Container and C_Container[name] then hooksecurefunc(C_Container, name, OnBagItemClick) end
  if _G[name] then hooksecurefunc(name, OnBagItemClick) end
end

local function LootSourceItem()
  if not (GetLootSourceInfo and C_Item and C_Item.GetItemIDByGUID) then return nil end
  local guid = GetLootSourceInfo(1)
  return guid and guid:match("^Item%-") and C_Item.GetItemIDByGUID(guid) or nil
end

StaticPopupDialogs.PROFIT_DISENCHANT_FOUND = {
  text = "%s", button1 = "Copy export", button2 = "Close",
  OnAccept = function() ns.ShowExport() end,
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- /prof testdisenchant: treat every result of the next disenchant as unexpected, to try the popup.
-- The disenchant is still recorded; the test doesn't stop real surprises from popping up later.
local testNextDisenchant = false
function ns.TestNextDisenchant()
  testNextDisenchant = true
  print("Profit: your next disenchant will show the \"didn't expect\" popup as a test.")
end

-- Record one disenchant's loot, and ask the player to share anything the data didn't predict.
local function RecordDisenchant(itemID)
  local test = testNextDisenchant
  testNextDisenchant = false
  local _, link, quality, level, _, _, _, _, _, _, _, class = GetItemInfo(itemID)
  local rec = ProfitDB.disenchant[itemID] or { r = {} }
  ProfitDB.disenchant[itemID] = rec
  rec.q, rec.il, rec.c = quality, level, class
  rec.n, rec.seen, rec.build = (rec.n or 0) + 1, time(), Build()

  local _, outcomes = ns.DisenchantValue(itemID)
  local expected = {}
  for _, o in ipairs(outcomes or {}) do expected[o.itemID] = o end
  local surprises = {}
  for slot = 1, GetNumLootItems() do
    local matID = ItemIDFromLink(GetLootSlotLink(slot))
    local count = select(3, GetLootSlotInfo(slot)) or 1
    if matID then
      local mat = rec.r[matID] or { n = 0, total = 0 }
      rec.r[matID] = mat
      mat.n, mat.total = mat.n + 1, mat.total + count
      mat.min, mat.max = math.min(mat.min or count, count), math.max(mat.max or count, count)
      local o = expected[matID]
      if test then
        table.insert(surprises, count .. "x " .. ns.ItemName(matID))
      elseif (not o or count < o.min or count > o.max) and not mat.flagged then
        mat.flagged = true
        table.insert(surprises, count .. "x " .. ns.ItemName(matID))
      end
    end
  end
  if #surprises > 0 then
    StaticPopup_Show("PROFIT_DISENCHANT_FOUND", string.format("%sProfit: disenchanting %s gave %s, which " ..
      "Profit didn't expect%s.\n\nPlease leave a comment at github.com/ExcEssIv3/profit/issues with your " ..
      "/prof export so we can add it.", test and "(Test) " or "", link or ns.ItemName(itemID), table.concat(surprises, ", "),
      outcomes and "" or " (it didn't know this item could be disenchanted)"))
  end
end

local function OnLoot()
  local pending = pendingDisenchant
  if not pending or GetTime() - pending.time > 5 then return end
  pendingDisenchant = nil
  local itemID = LootSourceItem() or pending.itemID
  if itemID then RecordDisenchant(itemID) end
end

-- Everything recorded, as one line of text players can copy and send us. tools/import_recorded.py
-- reads it. Format: "PROF1" then ";"-separated records:
--   t,spellID,skill,build,seen            trainer recipe
--   m,itemID,price,qty,limited,build,seen merchant item (limited is 1 or 0)
--   d,itemID,quality,itemLevel,class,times,build,seen,mat:n:total:min:max|...  disenchant results
function ns.ExportString()
  local parts = { "PROF1" }
  for spellID, t in pairs(ProfitDB.trainer) do
    table.insert(parts, string.format("t,%d,%d,%d,%d", spellID, t.skill, t.build or 0, t.seen or 0))
  end
  for itemID, m in pairs(ProfitDB.merchant) do
    table.insert(parts, string.format("m,%d,%s,%d,%d,%d,%d", itemID, tostring(m.price), m.qty or 1,
      m.limited and 1 or 0, m.build or 0, m.seen or 0))
  end
  for itemID, d in pairs(ProfitDB.disenchant) do
    local mats = {}
    for matID, m in pairs(d.r) do
      table.insert(mats, string.format("%d:%d:%d:%d:%d", matID, m.n, m.total, m.min, m.max))
    end
    table.insert(parts, string.format("d,%d,%d,%d,%d,%d,%d,%d,%s", itemID, d.q or -1, d.il or -1, d.c or -1,
      d.n, d.build or 0, d.seen or 0, table.concat(mats, "|")))
  end
  return table.concat(parts, ";")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_OPENED")
frame:SetScript("OnEvent", function(_, event, arg1, _, arg3)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    ns.FreshInstall = ProfitDB == nil -- no saved data yet; see Changelog.lua
    ProfitDB = ProfitDB or {}
    ProfitDB.version = 1
    ProfitDB.trainer = ProfitDB.trainer or {}
    ProfitDB.merchant = ProfitDB.merchant or {}
    ProfitDB.disenchant = ProfitDB.disenchant or {}
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if arg1 == "player" and arg3 == DISENCHANT then
      local clicked = clickedItem and GetTime() - clickedItem.time < 10 and clickedItem.itemID
      pendingDisenchant, clickedItem = { itemID = clicked, time = GetTime() }, nil
    end
  elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
    OnLoot()
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    ScanTrainer()
  else
    ScanMerchant()
  end
end)
