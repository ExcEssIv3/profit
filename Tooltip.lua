local addonName, ns = ...

-- Item tooltips: the expected disenchant value of gear that can be disenchanted and the cost of
-- crafting items a recipe makes. With Shift held, what it disenchants into, the craft's reagents and
-- its profit. Turned off with /prof tooltip (ProfitDB.tooltip = false).

local GOLD, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.8, 0.8, 0.8 }

local function Line(tooltip, left, right, l, r)
  tooltip:AddDoubleLine(left, right, l[1], l[2], l[3], r[1], r[2], r[3])
end

local function AddDisenchant(tooltip, itemID, shift)
  local value, outcomes = ns.DisenchantValue(itemID)
  if not outcomes then return end
  Line(tooltip, "Disenchant value", ns.FormatMoney(value), GOLD, WHITE)
  if not shift then return end
  for _, o in ipairs(outcomes) do
    local count = o.min == o.max and o.min or (o.min .. "-" .. o.max)
    Line(tooltip, string.format("  %s%% %sx %s", o.chance, count, ns.ItemName(o.itemID)),
      ns.FormatMoney(o.price) .. " each", GREY, GREY)
  end
end

local function AddCraft(tooltip, itemID, shift)
  local craft = ns.CraftInfo(itemID)
  if not craft then return end
  local recipe = ns.Recipes[craft.spellID]
  Line(tooltip, "Craft cost " .. (craft.known and "(known)" or "|cff808080(not known)|r"),
    craft.cost and ns.FormatMoney(craft.cost) or "?", GOLD, WHITE)
  if not shift then return end
  Line(tooltip, "  " .. recipe.p .. ": " .. recipe.n, recipe.m[2] > 1 and ("makes " .. recipe.m[2]) or " ", GREY, GREY)
  for _, r in ipairs(craft.reagents) do
    Line(tooltip, string.format("  %dx %s", r.count, ns.ItemName(r.itemID)),
      r.price and ns.FormatMoney(r.price * r.count) or "no price", GREY, GREY)
  end
  if craft.profit then
    Line(tooltip, "  Profit (auction house)", ns.FormatMoney(craft.profit),
      GREY, craft.profit < 0 and { 1, 0.25, 0.25 } or { 0.25, 0.75, 0.25 })
  end
end

local function AddLines(tooltip, itemID)
  if not itemID or (ProfitDB and ProfitDB.tooltip == false) then return end
  local shift = IsShiftKeyDown()
  AddDisenchant(tooltip, itemID, shift)
  AddCraft(tooltip, itemID, shift)
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
  print("Profit: disenchant values and craft costs in item tooltips " ..
    (ProfitDB.tooltip and "on" or "off; /prof tooltip to turn it back on"))
end
