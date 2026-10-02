local addonName, ns = ...

-- Global names (frames, slash commands) are prefixed "Profit". Avoid "Professions...": Blizzard's
-- own profession window is the global ProfessionsFrame.

-- The Profit window (/prof): a sortable, filterable list of recipes with a detail pane,
-- and the export window (/prof export). Built from basic templates that exist in both the
-- Classic and modern UI.

local ROWS, ROW_HEIGHT = 18, 18
local FILTERS = {
  { "known", "Known only" }, { "trainable", "Known + trainable" }, { "mine", "Known + learnable" },
  { "all", "All recipes" },
}
local COLUMNS = { -- key, title, width, justify
  { "profit", "Profit", 100, "RIGHT" },
  { "name", "Recipe", 200, "LEFT" },
  { "yellow", "Skill", 110, "LEFT" },
  { "cost", "Cost", 90, "RIGHT" },
  { "revenue", "Sells for", 90, "RIGHT" },
}
local LIST_WIDTH = 0
for _, c in ipairs(COLUMNS) do LIST_WIDTH = LIST_WIDTH + c[3] end

local state = { filter = 1, profession = nil, search = "", sortKey = "profit", ascending = false, offset = 0 }
local rows, window, Update = {}

local function Money(copper, colorSign)
  if not copper then return "|cff808080-|r" end
  local text = ns.FormatMoney(copper)
  if colorSign then return (copper < 0 and "|cffff4040" or "|cff40c040") .. text .. "|r" end
  return text
end

-- Profession dropdown choices: the character's own professions, or every profession for
-- "All recipes" (and when no professions have been detected yet). state.profession is false for
-- all professions, "main" for the character's primary professions, or a profession's name.
local function ProfessionChoices()
  local list = {}
  for name in pairs(ns.ProfessionNames) do
    if FILTERS[state.filter][1] == "all" or ns.SkillLevel(name) then table.insert(list, name) end
  end
  if #list == 0 then for name in pairs(ns.ProfessionNames) do table.insert(list, name) end end
  table.sort(list)
  local choices = { { false, "All professions" } }
  if next(ns.MainProfessions()) then table.insert(choices, { "main", "Main professions" }) end
  for _, name in ipairs(list) do table.insert(choices, { name, name }) end
  return choices
end

local function ProfessionLabel()
  if state.profession == "main" then return "Main professions" end
  return state.profession or "All professions"
end

-- Where an unknown recipe is learned: "trainer 40", "pattern 15", "trainer/pattern 15".
local SOURCE_LABELS = { trainer = "trainer", item = "pattern", trainer_inferred = "trainer?" }
local function SkillText(e)
  local text
  if e.known then
    text = "known"
  else
    local labels = {}
    for _, source in ipairs(ns.Sources(e.spellID)) do
      if SOURCE_LABELS[source] then table.insert(labels, SOURCE_LABELS[source]) end
    end
    text = (#labels > 0 and table.concat(labels, "/") or "learn") .. " " .. (ns.LearnSkill(e.spellID) or "?")
  end
  local code = e.color and ns.ColorCodes[e.color]
  return code and ("|c" .. code .. text .. "|r") or text
end

local function ShowDetail(spellID)
  state.selected = spellID
  window.detail:SetText(spellID and table.concat(ns.BreakdownLines(spellID), "\n") or
    "Select a recipe to see its materials, where to learn it, and its profit. " ..
    "Clicking a recipe you know also opens it in your profession window.")
end

function Update()
  if not window then return end
  local filter = FILTERS[state.filter]
  window.filterDropdown:Refresh(filter[2])
  window.professionDropdown:Refresh(ProfessionLabel())

  local profession = state.profession or nil
  if profession == "main" then profession = ns.MainProfessions() end
  local list = ns.Rank(filter[1], profession, state.search)
  for _, e in ipairs(list) do e.name, e.yellow = e.recipe.n, e.recipe.y end
  ns.SortRows(list, state.sortKey, state.ascending)
  state.list = list

  local maxOffset = math.max(0, #list - ROWS)
  state.offset = math.min(state.offset, maxOffset)
  window.scroll:SetMinMaxValues(0, maxOffset)
  window.scroll:SetValue(state.offset)
  if maxOffset > 0 then window.scroll:Show() else window.scroll:Hide() end

  for i, row in ipairs(rows) do
    local e = list[state.offset + i]
    row.e = e
    if e then
      local code = e.color and ns.ColorCodes[e.color]
      row.cells.name:SetText(code and ("|c" .. code .. e.recipe.n .. "|r") or e.recipe.n)
      row.cells.yellow:SetText(SkillText(e))
      row.cells.cost:SetText(Money(e.cost))
      row.cells.revenue:SetText(Money(e.revenue) .. (e.belowVendor and " |cffff4040v|r" or ""))
      row.cells.profit:SetText(Money(e.profit, true))
      if e.spellID == state.selected then row:LockHighlight() else row:UnlockHighlight() end
      row:Show()
    else
      row:Hide()
    end
  end

  local priced = 0
  for _, e in ipairs(list) do if e.profit then priced = priced + 1 end end
  local hasSkills = false
  for name in pairs(ns.ProfessionNames) do if ns.SkillLevel(name) then hasSkills = true end end
  if #list == 0 and filter[1] ~= "all" and not hasSkills then
    window.status:SetText("No professions detected yet: open one of your profession windows, or switch to All recipes.")
  else
    window.status:SetText(string.format("%d recipes, %d fully priced. Colors show your skill-up chance; " ..
      "\"v\" = sells for less than vendor value. Data build %s.", #list, priced, ns.DataBuild or "?"))
  end
  if state.selected then ShowDetail(state.selected) end
end

-- A dropdown of choices, each { value, label }. Uses the menu system where the client has it
-- (WowStyle1DropdownTemplate), and UIDropDownMenu otherwise. Call :Refresh(label) after the
-- selection or the choices change. d.inset is the transparent padding on each side, to subtract
-- when placing it.
local function CreateDropdown(parent, name, width, choices, selected, onSelect)
  if MenuUtil and DropdownButtonMixin then
    local d = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    d:SetWidth(width)
    d:SetupMenu(function(_, root)
      for _, c in ipairs(choices()) do
        root:CreateRadio(c[2], function() return selected() == c[1] end, function() onSelect(c[1]) end)
      end
    end)
    function d:Refresh(label)
      self:SetDefaultText(label)
      self:GenerateMenu()
    end
    d.inset = 0
    return d
  end

  local d = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(d, width - 20)
  UIDropDownMenu_Initialize(d, function(_, level)
    for _, c in ipairs(choices()) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.checked = c[2], selected() == c[1]
      info.func = function() onSelect(c[1]) end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  function d:Refresh(label) UIDropDownMenu_SetText(self, label) end
  d.inset = 16
  return d
end

local function CreateWindow()
  local f = CreateFrame("Frame", "ProfitWindow", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(LIST_WIDTH + 330, 470)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("HIGH")
  f:Hide()
  table.insert(UISpecialFrames, "ProfitWindow") -- close with Escape
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)
  f.title:SetText("Profit")

  -- Top bar: filter, profession, search.
  f.filterDropdown = CreateDropdown(f, "ProfitFilterDropdown", 140, function()
    local choices = {}
    for i, filter in ipairs(FILTERS) do table.insert(choices, { i, filter[2] }) end
    return choices
  end, function() return state.filter end, function(value)
    state.filter, state.offset = value, 0
    Update()
  end)
  f.filterDropdown:SetPoint("TOPLEFT", 12 - f.filterDropdown.inset, -30)

  f.professionDropdown = CreateDropdown(f, "ProfitProfessionDropdown", 140, ProfessionChoices,
    function() return state.profession or false end, function(value)
      state.profession, state.offset = value, 0
      Update()
    end)
  f.professionDropdown:SetPoint("LEFT", f.filterDropdown, "RIGHT", 6 - 2 * f.filterDropdown.inset, 0)

  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(160, 20)
  search:SetPoint("LEFT", f.professionDropdown, "RIGHT", 14 - f.professionDropdown.inset, 0)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(self)
    state.search, state.offset = self:GetText(), 0
    Update()
  end)
  search:SetScript("OnEscapePressed", search.ClearFocus)
  local searchLabel = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 0, 1)
  searchLabel:SetText("Search")

  -- Column headers; click to sort, click again to reverse.
  local x = 14
  for _, col in ipairs(COLUMNS) do
    local header = CreateFrame("Button", nil, f)
    header:SetSize(col[3], 18)
    header:SetPoint("TOPLEFT", x, -60)
    header:SetNormalFontObject("GameFontNormalSmall")
    header:SetHighlightFontObject("GameFontHighlightSmall")
    header:SetText(col[2])
    header:GetFontString():SetJustifyH(col[4])
    header:GetFontString():SetAllPoints()
    header:SetScript("OnClick", function()
      if state.sortKey == col[1] then
        state.ascending = not state.ascending
      else
        state.sortKey, state.ascending = col[1], col[1] == "name" or col[1] == "yellow" or col[1] == "cost"
      end
      Update()
    end)
    x = x + col[3]
  end

  -- Rows.
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 14, -78 - (i - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.cells = {}
    local cx = 0
    for _, col in ipairs(COLUMNS) do
      local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      cell:SetSize(col[3] - 6, ROW_HEIGHT)
      cell:SetPoint("LEFT", cx, 0)
      cell:SetJustifyH(col[4])
      cell:SetWordWrap(false)
      row.cells[col[1]] = cell
      cx = cx + col[3]
    end
    -- Click shows the breakdown, and opens the game's profession window at recipes you know.
    row:SetScript("OnClick", function(self)
      if not self.e then return end
      ShowDetail(self.e.spellID)
      Update()
      if self.e.known then ns.OpenRecipe(self.e.spellID) end
    end)
    rows[i] = row
  end

  -- Scrolling: mouse wheel over the list, or drag the bar.
  local scroll = CreateFrame("Slider", nil, f)
  scroll:SetOrientation("VERTICAL")
  scroll:SetSize(12, ROWS * ROW_HEIGHT)
  scroll:SetPoint("TOPLEFT", 14 + LIST_WIDTH + 2, -78)
  scroll:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scroll:GetThumbTexture():SetSize(18, 24)
  scroll:SetValueStep(1)
  local track = scroll:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0, 0, 0, 0.4)
  scroll:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value + 0.5)
    if value ~= state.offset then state.offset = value Update() end
  end)
  f.scroll = scroll
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    local low, high = scroll:GetMinMaxValues()
    scroll:SetValue(math.max(low, math.min(high, state.offset - delta * 3)))
  end)

  -- Detail pane.
  local detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail:SetPoint("TOPLEFT", 14 + LIST_WIDTH + 24, -60)
  detail:SetPoint("BOTTOMRIGHT", -14, 40)
  detail:SetJustifyH("LEFT")
  detail:SetJustifyV("TOP")
  detail:SetSpacing(2)
  f.detail = detail

  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.status:SetPoint("BOTTOMLEFT", 14, 14)
  f.status:SetPoint("BOTTOMRIGHT", -14, 14)
  f.status:SetJustifyH("LEFT")

  f:SetScript("OnShow", Update)
  window = f
  ShowDetail(nil)
end

function ns.ToggleWindow()
  if not window then CreateWindow() end
  window:SetShown(not window:IsShown())
end

-- Prices, recordings and known recipes can change many times in a row (e.g. during a scan);
-- redraw at most once per half second.
local pending = false
function ns.Refresh()
  if not (window and window:IsShown()) or pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    Update()
  end)
end

-- Export window: the text is selected so the player can press Ctrl+C.
local exportWindow
function ns.ShowExport()
  if not exportWindow then
    local f = CreateFrame("Frame", "ProfitExportWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(460, 240)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    table.insert(UISpecialFrames, "ProfitExportWindow")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Profit: share your recordings")
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", 14, -32)
    help:SetPoint("TOPRIGHT", -14, -32)
    help:SetJustifyH("LEFT")
    help:SetText("Press Ctrl+C (Cmd+C on Mac) to copy, then post it as an issue at " ..
      "github.com/ExcEssIv3/profit/issues. It contains only trainer skill levels and merchant " ..
      "items you've seen.")
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -78)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(400)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Keep the text as exported if the player types into it.
    edit:SetScript("OnTextChanged", function(self, userInput)
      if userInput then self:SetText(f.text) self:HighlightText() end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    exportWindow = f
  end
  exportWindow.text = ns.ExportString()
  exportWindow.edit:SetText(exportWindow.text)
  exportWindow:Show()
  exportWindow.edit:SetFocus()
  exportWindow.edit:HighlightText()
end
