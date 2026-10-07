local addonName, ns = ...

-- Global names (frames, slash commands) are prefixed "Profit". Avoid "Professions...": Blizzard's
-- own profession window is the global ProfessionsFrame.

-- The Profit window (/prof): a sortable, filterable list of recipes with a detail pane,
-- and the export window (/prof export). Built from basic templates that exist in both the
-- Classic and modern UI.

local ROWS, ROW_HEIGHT = 18, 18
-- "disenchant" lists auction house gear to buy and disenchant instead of recipes; only offered
-- to enchanters.
local FILTERS = {
  { "known", "Known only" }, { "trainable", "Known + trainable" }, { "mine", "Known + learnable" },
  { "all", "All recipes" }, { "disenchant", "Disenchant from AH" },
}
-- key, title, width, justify, title in "Disenchant from AH" ("" hides the column). fit: shrink to
-- the widest value in the list (width is the most it takes), and give the rest to the "name" column.
local COLUMNS = {
  { "profit", "Profit", 100, "RIGHT", "Profit", fit = true },
  { "name", "Recipe", 180, "LEFT", "Item" },
  { "yellow", "Skill", 110, "LEFT", "Skill" },
  { "cost", "Cost", 90, "RIGHT", "Buy for" },
  { "revenue", "Sells for", 90, "RIGHT", "Disenchant" },
  { "deProfit", "Disenchant", 90, "RIGHT", "" }, -- profit if disenchanted instead of sold
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

local function DisenchantMode() return FILTERS[state.filter][1] == "disenchant" end

-- key is a recipe's spell ID, or "item:<id>" for an item in Disenchant from AH.
local function ShowDetail(key)
  state.selected = key
  local itemID = type(key) == "string" and tonumber(key:match("^item:(%d+)"))
  local lines = itemID and ns.DisenchantLines(itemID) or key and ns.BreakdownLines(key)
  window.detail:SetText(lines and table.concat(lines, "\n") or DisenchantMode() and
    "Gear on the auction house worth more disenchanted than its price, from your last Auctionator " ..
    "scan. Select an item for what it disenchants into; with the auction house open, clicking it " ..
    "also searches for it." or
    "Select a recipe to see its materials, where to learn it, and its profit. " ..
    "Clicking a recipe you know also opens it in your profession window.")
end

-- Column widths for this list: fitted columns as wide as their widest text, "name" takes the rest.
local function ColumnWidths(list)
  local widths, spare = {}, 0
  for _, col in ipairs(COLUMNS) do
    widths[col[1]] = col[3]
    if col.fit then
      local measure = window.measure
      measure:SetText(col[2])
      local widest = measure:GetStringWidth()
      for _, e in ipairs(list) do
        measure:SetText(Money(e[col[1]], true))
        widest = math.max(widest, measure:GetStringWidth())
      end
      widths[col[1]] = math.min(col[3], math.ceil(widest) + 12)
      spare = spare + col[3] - widths[col[1]]
    end
  end
  widths.name = widths.name + spare
  return widths
end

local function Layout(widths)
  local x = 0
  for i, col in ipairs(COLUMNS) do
    local width = widths[col[1]]
    window.headers[i]:SetWidth(width)
    window.headers[i]:SetPoint("TOPLEFT", 14 + x, -60)
    for _, row in ipairs(rows) do
      row.cells[col[1]]:SetWidth(width - 6)
      row.cells[col[1]]:SetPoint("LEFT", x, 0)
    end
    x = x + width
  end
end

local function SetRow(row, e)
  if DisenchantMode() then
    row.cells.name:SetText(e.name)
    row.cells.yellow:SetText(e.skill or "?")
    row.cells.cost:SetText(Money(e.cost))
    row.cells.revenue:SetText(Money(e.deValue))
    row.cells.deProfit:SetText("")
  else
    local code = e.color and ns.ColorCodes[e.color]
    row.cells.name:SetText(code and ("|c" .. code .. e.name .. "|r") or e.name)
    row.cells.yellow:SetText(SkillText(e))
    row.cells.cost:SetText(Money(e.cost))
    row.cells.revenue:SetText(Money(e.revenue) .. (e.belowVendor and " |cffff4040v|r" or ""))
    row.cells.deProfit:SetText(Money(e.deProfit, true))
  end
  row.cells.profit:SetText(Money(e.profit, true))
end

function Update()
  if not window then return end
  local filter = FILTERS[state.filter]
  window.filterDropdown:Refresh(filter[2])
  window.professionDropdown:Refresh(ProfessionLabel())
  local deMode = DisenchantMode()
  window.professionDropdown:SetShown(not deMode)
  for _, header in ipairs(window.headers) do header:SetText(deMode and header.col[5] or header.col[2]) end

  local list, tooHigh
  if deMode then
    list, tooHigh = ns.DisenchantDeals(state.search)
    for _, e in ipairs(list) do e.yellow, e.revenue = e.skill, e.deValue end
  else
    local profession = state.profession or nil
    if profession == "main" then profession = ns.MainProfessions() end
    list = ns.Rank(filter[1], profession, state.search)
    for _, e in ipairs(list) do e.yellow = e.recipe.y end
  end
  ns.SortRows(list, state.sortKey, state.ascending)
  state.list = list
  Layout(ColumnWidths(list))

  local maxOffset = math.max(0, #list - ROWS)
  state.offset = math.min(state.offset, maxOffset)
  window.scroll:SetMinMaxValues(0, maxOffset)
  window.scroll:SetValue(state.offset)
  if maxOffset > 0 then window.scroll:Show() else window.scroll:Hide() end

  for i, row in ipairs(rows) do
    local e = list[state.offset + i]
    row.e = e
    if e then
      SetRow(row, e)
      if e.key == state.selected then row:LockHighlight() else row:UnlockHighlight() end
      row:Show()
    else
      row:Hide()
    end
  end

  local priced = 0
  for _, e in ipairs(list) do if e.profit then priced = priced + 1 end end
  local hasSkills = false
  for name in pairs(ns.ProfessionNames) do if ns.SkillLevel(name) then hasSkills = true end end
  if deMode then
    window.status:SetText(string.format("%d items worth more disenchanted than their auction price%s. " ..
      "Prices from your last Auctionator scan.", #list,
      tooHigh > 0 and string.format(" (%d more need more Enchanting skill)", tooHigh) or ""))
  elseif #list == 0 and filter[1] ~= "all" and not hasSkills then
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
    for i, filter in ipairs(FILTERS) do
      if filter[1] ~= "disenchant" or ns.SkillLevel("Enchanting") or i == state.filter then
        table.insert(choices, { i, filter[2] })
      end
    end
    return choices
  end, function() return state.filter end, function(value)
    -- Recipes and items are different rows: keep the selection only within one kind.
    if (FILTERS[value][1] == "disenchant") ~= DisenchantMode() then state.selected = nil end
    state.filter, state.offset = value, 0
    ShowDetail(state.selected)
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

  -- Column headers; click to sort, click again to reverse. Headers are left-aligned (a right-aligned
  -- first header would run into the next one); Update() sets their titles.
  local x = 14
  f.headers = {}
  for _, col in ipairs(COLUMNS) do
    local header = CreateFrame("Button", nil, f)
    header.col = col
    header:SetSize(col[3], 18)
    header:SetPoint("TOPLEFT", x, -60)
    header:SetNormalFontObject("GameFontNormalSmall")
    header:SetHighlightFontObject("GameFontHighlightSmall")
    header:SetText(col[2])
    header:GetFontString():SetJustifyH(col[1] == "profit" and "LEFT" or col[4])
    header:GetFontString():SetAllPoints()
    table.insert(f.headers, header)
    header:SetScript("OnClick", function()
      if header:GetText() == "" then return end
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
    -- Click shows the breakdown, and opens the game's profession window at recipes you know, or
    -- searches the auction house (through Auctionator, when it's open) for an item to disenchant.
    row:SetScript("OnClick", function(self)
      if not self.e then return end
      ShowDetail(self.e.key)
      Update()
      if self.e.itemID then
        pcall(Auctionator.API.v1.MultiSearchExact, addonName, { self.e.name })
      elseif self.e.known then
        ns.OpenRecipe(self.e.spellID)
      end
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

  f.measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- for ColumnWidths
  f.measure:SetAlpha(0) -- invisible but laid out, so its width can be measured

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

-- A window of selected text for the player to copy with Ctrl+C: the export string, /prof debug.
local textWindow
function ns.ShowText(titleText, helpText, text)
  if not textWindow then
    local f = CreateFrame("Frame", "ProfitTextWindow", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(520, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    table.insert(UISpecialFrames, "ProfitTextWindow")
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    f.help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.help:SetPoint("TOPLEFT", 14, -32)
    f.help:SetPoint("TOPRIGHT", -14, -32)
    f.help:SetJustifyH("LEFT")
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -78)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("ChatFontSmall")
    edit:SetWidth(460)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Keep the text as shown if the player types into it.
    edit:SetScript("OnTextChanged", function(self, userInput)
      if userInput then self:SetText(f.text) self:HighlightText() end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    textWindow = f
  end
  textWindow.title:SetText(titleText)
  textWindow.help:SetText(helpText)
  textWindow.text = text
  textWindow.edit:SetText(text)
  textWindow:Show()
  textWindow.edit:SetFocus()
  textWindow.edit:HighlightText()
end

function ns.ShowExport()
  ns.ShowText("Profit: share your recordings", "Press Ctrl+C (Cmd+C on Mac) to copy, then post it as an issue " ..
    "at github.com/ExcEssIv3/profit/issues. It contains only trainer skill levels, merchant items and " ..
    "disenchant results you've seen.", ns.ExportString())
end
