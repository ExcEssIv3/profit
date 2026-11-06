local addonName, ns = ...

-- Minimap button through LibDataBroker + LibDBIcon (embedded in Libs/ by the packager), so
-- minimap button collectors and the addon compartment can manage it.
-- ProfitDB.minimap is LibDBIcon's settings table: { minimapPos = degrees, hide = bool, lock = bool }.

local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

local function Settings()
  local settings = ProfitDB.minimap or {}
  ProfitDB.minimap = settings
  -- Older versions drew their own button and saved its position as "angle".
  if settings.angle then
    settings.minimapPos, settings.angle = settings.angle % 360, nil
  end
  settings.minimapPos = settings.minimapPos or 200
  return settings
end

function ns.ToggleMinimapButton()
  if not DBIcon then
    print("Profit: the minimap button needs LibDBIcon, which is missing from this copy of Profit.")
    return
  end
  local settings = Settings()
  settings.hide = not settings.hide
  if settings.hide then DBIcon:Hide(addonName) else DBIcon:Show(addonName) end
  print("Profit: minimap button " .. (settings.hide and "hidden; /prof minimap to show it again" or "shown"))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
  if not (LDB and DBIcon) then return end
  local launcher = LDB:NewDataObject(addonName, {
    type = "launcher",
    label = "Profit",
    icon = ICON,
    OnClick = function() ns.ToggleWindow() end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine("Profit")
      tooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
      tooltip:AddLine("/prof minimap to hide this button.", 0.6, 0.6, 0.6)
    end,
  })
  DBIcon:Register(addonName, launcher, Settings())
end)
