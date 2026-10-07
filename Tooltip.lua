local addonName, ns = ...

-- Item tooltips: the expected disenchant value of gear that can be disenchanted, and with Shift
-- held, what it disenchants into. Turned off with /prof tooltip (ProfitDB.tooltip = false).

local function AddLines(tooltip, itemID)
  if not itemID or (ProfitDB and ProfitDB.tooltip == false) then return end
  local value, outcomes = ns.DisenchantValue(itemID)
  if not outcomes then return end
  tooltip:AddDoubleLine("Disenchant value", ns.FormatMoney(value), 1, 0.82, 0, 1, 1, 1)
  if not IsShiftKeyDown() then return end
  for _, o in ipairs(outcomes) do
    local count = o.min == o.max and o.min or (o.min .. "-" .. o.max)
    tooltip:AddDoubleLine(string.format("  %s%% %sx %s", o.chance, count, ns.ItemName(o.itemID)),
      ns.FormatMoney(o.price) .. " each", 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
  end
end

-- Modern clients pass tooltip data to post-calls; older ones fire OnTooltipSetItem.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    AddLines(tooltip, data and data.id)
  end)
else
  local function OnSetItem(tooltip)
    local _, link = tooltip:GetItem()
    AddLines(tooltip, link and tonumber(link:match("item:(%d+)")))
  end
  for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
    local tooltip = _G[name]
    if tooltip and tooltip.HookScript then pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", OnSetItem) end
  end
end

function ns.ToggleTooltip()
  ProfitDB.tooltip = ProfitDB.tooltip == false
  print("Profit: disenchant value in item tooltips " .. (ProfitDB.tooltip and "on" or "off; /prof tooltip to turn it back on"))
end
