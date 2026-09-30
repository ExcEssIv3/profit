local addonName, ns = ...

-- Tracks this character's professions, into ProfitCharDB (per character):
--   skills[profession] = current skill level
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
  local known = ProfitCharDB.known[profession] or {}
  for _, spellID in ipairs(spellIDs) do
    if ns.Recipes[spellID] then known[spellID] = true end
  end
  ProfitCharDB.known[profession] = known
  ns.Refresh()
end

local function StoreSkill(profession, rank)
  if profession and rank and ns.ProfessionNames[profession] and ProfitCharDB.skills[profession] ~= rank then
    ProfitCharDB.skills[profession] = rank
    ns.Refresh()
  end
end

-- Current skill in every profession, from the character's skill list. A collapsed header
-- hides its skills, so only drop professions (e.g. after unlearning) on a complete read.
local function ScanSkills()
  local found, complete = {}, true
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, isExpanded, rank = GetSkillLineInfo(i)
      if isHeader and not isExpanded then complete = false end
      if not isHeader and ns.ProfessionNames[name] then found[name] = rank end
    end
  elseif GetProfessions and GetProfessionInfo then
    for _, index in pairs({ GetProfessions() }) do
      local name, _, rank = GetProfessionInfo(index)
      if ns.ProfessionNames[name] then found[name] = rank end
    end
  else
    return
  end
  if complete then
    for name in pairs(ProfitCharDB.skills) do
      if not found[name] then ProfitCharDB.skills[name] = nil end
    end
  end
  for name, rank in pairs(found) do StoreSkill(name, rank) end
  ns.Refresh()
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
  if info then StoreSkill(profession, info.skillLevel) end
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
  local profession, rank = GetTradeSkillLine()
  ScanClassic(GetNumTradeSkills(), GetTradeSkillInfo, GetTradeSkillRecipeLink, profession)
  StoreSkill(profession, rank)
end

local function ScanCraft()
  ScanClassic(GetNumCrafts(), function(i)
    local name, _, kind = GetCraftInfo(i)
    return name, kind
  end, GetCraftRecipeLink or GetCraftItemLink, (GetCraftDisplaySkillLine()))
  local profession, rank = GetCraftDisplaySkillLine()
  StoreSkill(profession, rank)
end

-- Open the game's profession window at a recipe this character knows. Returns true if it did.
-- The modern window can be opened directly. Classic's can't (only a spell cast opens it), so
-- there we can only select the recipe in a window that's already open.
local function SelectInClassicWindow(spellID)
  local recipe = ns.Recipes[spellID]
  local windows = {
    { TradeSkillFrame, GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillRecipeLink, "TradeSkillFrame_SetSelection", "TradeSkillFrame_Update" },
    { CraftFrame, GetCraftDisplaySkillLine, GetNumCrafts, GetCraftInfo, GetCraftRecipeLink or GetCraftItemLink, "CraftFrame_SetSelection", "CraftFrame_Update" },
  }
  for _, w in ipairs(windows) do
    local frame, line, count, info, link, select, update = unpack(w)
    if frame and frame:IsShown() and line() == recipe.p then
      for i = 1, count() do
        if SpellIDFromLink(link and link(i)) == spellID or info(i) == recipe.n then
          _G[select](i)
          if _G[update] then _G[update]() end
          return true
        end
      end
    end
  end
  return false
end

function ns.OpenRecipe(spellID)
  if not ns.IsKnown(spellID) then return false end
  if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
    C_TradeSkillUI.OpenRecipe(spellID)
    return true
  end
  if SelectInClassicWindow(spellID) then return true end
  print("Profit: open your " .. ns.Recipes[spellID].p .. " window first, then click the recipe again.")
  return false
end

-- Current skill level, or nil if this character doesn't have the profession (or we haven't read it).
function ns.SkillLevel(profession)
  return ProfitCharDB and ProfitCharDB.skills[profession]
end

-- true if known, false if the profession has been scanned and it isn't there, nil if we can't tell.
function ns.IsKnown(spellID)
  if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
  local recipe = ns.Recipes[spellID]
  local known = ProfitCharDB and ProfitCharDB.known[recipe.p]
  if known then return known[spellID] == true end
  return nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
  pcall(frame.RegisterEvent, frame, event) -- not every client has every event
end
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    ProfitCharDB = ProfitCharDB or {}
    ProfitCharDB.known = ProfitCharDB.known or {}
    ProfitCharDB.skills = ProfitCharDB.skills or {}
  elseif event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then
    ScanSkills()
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    ScanCraft()
  else
    ScanTradeSkill()
  end
end)
