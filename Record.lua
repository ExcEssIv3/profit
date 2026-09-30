local addonName, ns = ...

-- Records what the client data can't tell us, into ProfessionsDB (account-wide):
--   trainer[spellID]  = { skill, prof, cost, seen, build }  skill needed to learn a trainer recipe
--   merchant[itemID]  = { price, qty, limited, seen, build } items merchants sell for gold
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
          ProfessionsDB.trainer[spellID] = {
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
      ProfessionsDB.merchant[itemID] = {
        price = price / math.max(qty or 1, 1), qty = qty,
        limited = (numAvailable or -1) >= 0 or nil, seen = now, build = build,
      }
    end
  end
  ns.Refresh()
end

ns.ScanTrainer = ScanTrainer

-- Everything recorded, as one line of text players can copy and send us. tools/import_recorded.py
-- reads it. Format: "PROF1" then ";"-separated records:
--   t,spellID,skill,build,seen            trainer recipe
--   m,itemID,price,qty,limited,build,seen merchant item (limited is 1 or 0)
function ns.ExportString()
  local parts = { "PROF1" }
  for spellID, t in pairs(ProfessionsDB.trainer) do
    table.insert(parts, string.format("t,%d,%d,%d,%d", spellID, t.skill, t.build or 0, t.seen or 0))
  end
  for itemID, m in pairs(ProfessionsDB.merchant) do
    table.insert(parts, string.format("m,%d,%s,%d,%d,%d,%d", itemID, tostring(m.price), m.qty or 1,
      m.limited and 1 or 0, m.build or 0, m.seen or 0))
  end
  return table.concat(parts, ";")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    ProfessionsDB = ProfessionsDB or {}
    ProfessionsDB.version = 1
    ProfessionsDB.trainer = ProfessionsDB.trainer or {}
    ProfessionsDB.merchant = ProfessionsDB.merchant or {}
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    ScanTrainer()
  else
    ScanMerchant()
  end
end)
