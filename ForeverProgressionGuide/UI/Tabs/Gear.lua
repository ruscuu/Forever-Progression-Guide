-- Pestaña Equipo: lo que llevas puesto y las mejoras que tienes en las bolsas,
-- comparadas por estadísticas con pesos según tu clase y especialización.
local _, ns = ...

local UI, G, W = ns.UI, ns.Gear, ns.Compare
local L = ns.L

local mode = "bags"

local SLOT_KEYS = {}
for _, slot in ipairs(G.SLOTS) do SLOT_KEYS[slot.id] = slot.key end

local function renderEquipped(panel)
  local equipped = G.Equipped()
  local weak, average = G.WeakSlots()
  local isWeak = {}
  for _, e in ipairs(weak) do isWeak[e.slot] = true end
  panel.intro:SetText(string.format(L.GEAR_INTRO, average and string.format("%.1f", average) or "?"))
  panel.list:SetData(equipped, function(row, e)
    row.icon:SetTexture(GetInventoryItemTexture("player", e.slot) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    local item = e.link or UI.Color("9d9d9d", e.notApplicable and L.GEAR_NOT_APPLICABLE or L.GEAR_EMPTY)
    local marker = isWeak[e.slot] and UI.Color("ff9933", "  (" .. L.GEAR_WEAK .. ")") or ""
    row.left:SetText(UI.Color("ffd100", L["SLOT_" .. e.key]) .. "  " .. item .. marker)
    row.right:SetText(e.itemLevel and string.format(L.ITEM_LEVEL_SHORT, e.itemLevel) or "")
  end)
  panel.list.onEnter = function(e, row) if e.link then UI.Tooltip(row, nil, e.link) end end
end

local function currentRole()
  local selection = ns.ClassFilter.Current()
  return selection.isPlayer and selection.role or nil
end

local function renderBags(panel)
  local player = ns.Compat.Player()
  local role = currentRole()
  local upgrades = W.BagUpgrades(player.class, role, player.level)
  local profile = L["PROFILE_" .. string.upper(W.Profile(player.class, role))]
  panel.intro:SetText(string.format(#upgrades > 0 and L.BAGS_INTRO or L.BAGS_EMPTY, profile))
  panel.list:SetData(upgrades, function(row, u)
    row.icon:SetTexture(u.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local target = UI.Color("9d9d9d", "  → " .. L["SLOT_" .. (SLOT_KEYS[u.slot] or "HEAD")])
    local future = u.future and UI.Color("ff5050", "  " .. string.format(L.ITEM_REQ_SHORT, u.future)) or ""
    row.left:SetText(u.link .. target .. future .. "   " .. W.DiffText(u.diffs, 3))
    row.right:SetText(UI.Color("40ff40", string.format("+%d", math.floor(u.delta + 0.5))))
  end)
  panel.list.onEnter = function(u, row) UI.Tooltip(row, nil, u.link) end
end

UI.RegisterTab({
  key = "gear",
  Build = function(panel)
    panel.bags = UI.Button(panel, "", 180, function() mode = "bags" UI.Select("gear") end)
    panel.bags:SetPoint("TOPLEFT", 0, 0)
    panel.equipped = UI.Button(panel, "", 140, function() mode = "equipped" UI.Select("gear") end)
    panel.equipped:SetPoint("LEFT", panel.bags, "RIGHT", 4, 0)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, -30)
    panel.intro:SetPoint("RIGHT", 0, 0)
    panel.list = UI.List(panel, 24, UI.IconRow)
    panel.list:SetPoints(0, -64, 0, 0)
  end,
  Refresh = function(panel)
    panel.bags:SetText(L.GEAR_MODE_BAGS)
    panel.equipped:SetText(L.GEAR_MODE_EQUIPPED)
    panel.bags:SetActive(mode == "bags")
    panel.equipped:SetActive(mode == "equipped")
    if mode == "bags" then renderBags(panel) else renderEquipped(panel) end
  end,
})

-- Las bolsas cambian a menudo: se redibuja solo si la pestaña está a la vista.
ns.On("BAG_UPDATE_DELAYED", function() if UI.IsShown("gear") then UI.Select("gear") end end)
