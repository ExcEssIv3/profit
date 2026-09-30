local addonName, ns = ...

-- Minimap button: click opens the window, drag moves it around the minimap edge.
-- Position and visibility are saved in ProfessionsDB.minimap = { angle = degrees, hide = bool }.

local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local button

local function Settings()
  ProfessionsDB.minimap = ProfessionsDB.minimap or { angle = 200 }
  return ProfessionsDB.minimap
end

local function Place()
  local angle = math.rad(Settings().angle)
  local radius = Minimap:GetWidth() / 2 + 5
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
  Place()
end

local function Create()
  button = CreateFrame("Button", "ProfessionsAddonMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(20, 20)
  background:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(53, 53)
  ring:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function() ns.ToggleWindow() end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Professions")
    GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
    GameTooltip:AddLine("/prof minimap to hide this button.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Place()
end

function ns.ToggleMinimapButton()
  local settings = Settings()
  settings.hide = not settings.hide
  button:SetShown(not settings.hide)
  print("Professions: minimap button " .. (settings.hide and "hidden; /prof minimap to show it again" or "shown"))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  Create()
  button:SetShown(not Settings().hide)
end)
