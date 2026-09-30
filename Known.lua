local addonName, ns = ...

-- Tracks which recipes this character knows, into ProfessionsCharDB (per character):
--   known[profession] = { [spellID] = true, ... }  added to each time that profession's window opens
-- Only ever added to: Classic's window filters (e.g. "Have Materials") hide recipes you know.
-- Supports both the modern C_TradeSkillUI API and Classic's trade skill / craft (Enchanting) APIs.

local function RecipesNamed(profession, name)
  local matches = {}
  for spellID, recipe in pairs(ns.Recipes) do
    if recipe.p == profession and recipe.n == name then table.insert(matches, spellID) end
  end
  return matches
end

local function SpellIDFromLink(link)
  return link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
end

local function Store(profession, spellIDs)
  if not (profession and ns.ProfessionNames[profession]) then return end
  local known = ProfessionsCharDB.known[profession] or {}
  for _, spellID in ipairs(spellIDs) do
    if ns.Recipes[spellID] then known[spellID] = true end
  end
  ProfessionsCharDB.known[profession] = known
end

local function ScanModern()
  local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  local profession = info and info.professionName
  if not profession and C_TradeSkillUI.GetTradeSkillLine then
    profession = select(2, C_TradeSkillUI.GetTradeSkillLine())
  end
  local spellIDs = {}
  for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
    local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if recipe and recipe.learned then table.insert(spellIDs, recipeID) end
  end
  Store(profession, spellIDs)
end

-- Classic lists recipes by index. Take the spell ID from the recipe link when there is one,
-- otherwise match the name within the profession.
local function ScanClassic(count, info, recipeLink, profession)
  local spellIDs = {}
  for i = 1, count do
    local name, kind = info(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local spellID = SpellIDFromLink(recipeLink and recipeLink(i))
      if spellID and ns.Recipes[spellID] then
        table.insert(spellIDs, spellID)
      else
        for _, match in ipairs(RecipesNamed(profession, name)) do table.insert(spellIDs, match) end
      end
    end
  end
  Store(profession, spellIDs)
end

local function ScanTradeSkill()
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then return ScanModern() end
  ScanClassic(GetNumTradeSkills(), GetTradeSkillInfo, GetTradeSkillRecipeLink, (GetTradeSkillLine()))
end

local function ScanCraft()
  ScanClassic(GetNumCrafts(), function(i)
    local name, _, kind = GetCraftInfo(i)
    return name, kind
  end, GetCraftRecipeLink or GetCraftItemLink, (GetCraftDisplaySkillLine()))
end

-- true if known, false if the profession has been scanned and it isn't there, nil if we can't tell.
function ns.IsKnown(spellID)
  if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
  local recipe = ns.Recipes[spellID]
  local known = ProfessionsCharDB and ProfessionsCharDB.known[recipe.p]
  if known then return known[spellID] == true end
  return nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(frame.RegisterEvent, frame, event) -- not every client has every event
end
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    ProfessionsCharDB = ProfessionsCharDB or {}
    ProfessionsCharDB.known = ProfessionsCharDB.known or {}
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    ScanCraft()
  else
    ScanTradeSkill()
  end
end)
