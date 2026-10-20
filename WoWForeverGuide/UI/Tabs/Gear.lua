-- Pestaña Equipo: equipo actual y ranuras débiles según el nivel de objeto.
local _, ns = ...

local UI, G = ns.UI, ns.Gear
local L = ns.L

UI.RegisterTab({
  key = "gear",
  Build = function(panel)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, 0)
    panel.intro:SetPoint("RIGHT", 0, 0)
    panel.list = UI.List(panel, 22)
    panel.list:SetPoints(0, -48, 0, 0)
    panel.list.onEnter = function(entry, row) if entry.link then UI.Tooltip(row, nil, entry.link) end end
  end,
  Refresh = function(panel)
    local equipped = G.Equipped()
    local weak, average = G.WeakSlots()
    local isWeak = {}
    for _, e in ipairs(weak) do isWeak[e.slot] = true end
    panel.intro:SetText(string.format(L.GEAR_INTRO, average and string.format("%.1f", average) or "?"))
    panel.list:SetData(equipped, function(row, e)
      local slotName = L["SLOT_" .. e.key]
      local item = e.link or UI.Color("9d9d9d", e.notApplicable and L.GEAR_NOT_APPLICABLE or L.GEAR_EMPTY)
      local marker = isWeak[e.slot] and UI.Color("ff9933", "  (" .. L.GEAR_WEAK .. ")") or ""
      row.left:SetText(UI.Color("ffd100", slotName) .. "  " .. item .. marker)
      row.right:SetText(e.itemLevel and tostring(e.itemLevel) or "")
    end)
  end,
})
