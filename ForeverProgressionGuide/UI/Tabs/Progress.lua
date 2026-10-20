-- Pestaña Progresión: próximos objetivos en tarjetas, con su explicación.
local _, ns = ...

local UI, O = ns.UI, ns.Objectives
local L = ns.L

local CARD_HEIGHT = 64
local CARD_GAP = 6

-- Icono de cada tipo de objetivo.
local KIND_ICONS = {
  dungeon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  next = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  gear = "Interface\\Icons\\INV_Chest_Chain_05",
  bag = "Interface\\Icons\\INV_Misc_Bag_08",
  class = "Interface\\Icons\\INV_Misc_Book_11",
  zone = "Interface\\Icons\\INV_Misc_Map_01",
  explore = "Interface\\Icons\\INV_Misc_Spyglass_02",
  info = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local CONFIDENCE_RGB = {
  high = { 0.25, 1, 0.25 }, medium = { 1, 0.82, 0 }, low = { 1, 0.6, 0.2 }, none = { 0.6, 0.6, 0.6 },
}

local function buildCard(content, list)
  local row = CreateFrame("Button", nil, content)
  local card = CreateFrame("Frame", nil, row)
  card:SetPoint("TOPLEFT", 0, 0)
  card:SetPoint("BOTTOMRIGHT", 0, CARD_GAP)
  UI.Box(card, UI.THEME.panel)
  row.hover = card:CreateTexture(nil, "BACKGROUND", nil, -6)
  row.hover:SetPoint("TOPLEFT", 1, -1)
  row.hover:SetPoint("BOTTOMRIGHT", -1, 1)
  UI.Paint(row.hover, { 1, 1, 1, 0.05 })
  row.hover:Hide()

  row.bar = card:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT", 1, -1)
  row.bar:SetPoint("BOTTOMLEFT", 1, 1)
  row.bar:SetWidth(3)

  row.icon = card:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(36, 36)
  row.icon:SetPoint("LEFT", 12, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.title = UI.Label(card, "GameFontNormal")
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
  row.title:SetPoint("RIGHT", -190, 0)
  row.title:SetWordWrap(false)
  row.reason = UI.Label(card, "GameFontHighlightSmall")
  row.reason:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
  row.reason:SetPoint("RIGHT", -190, 0)
  row.reason:SetHeight(26)
  row.tag = UI.Label(card, "GameFontDisableSmall", "RIGHT")
  row.tag:SetPoint("BOTTOMRIGHT", -8, 7)

  local function action(state)
    return function() O.SetState(row.item.id, state) end
  end
  row.done = UI.Button(card, "", 58, action(O.DONE))
  row.later = UI.Button(card, "", 58, action(O.POSTPONED))
  row.dismiss = UI.Button(card, "", 58, action(O.DISMISSED))
  for i, b in ipairs({ row.done, row.later, row.dismiss }) do
    b:SetHeight(18)
    b:SetPoint("TOPRIGHT", -(3 - i) * 60 - 8, -8)
  end

  row:SetScript("OnEnter", function(self) self.hover:Show() end)
  row:SetScript("OnLeave", function(self) self.hover:Hide() end)
  row:SetScript("OnClick", function(self)
    if self.item.target then UI.Select(self.item.target.tab, self.item.target) end
  end)
  return row
end

UI.RegisterTab({
  key = "progress",
  Build = function(panel)
    panel.heading = UI.Header(panel, 300)
    panel.heading:SetPoint("TOPLEFT", 0, 0)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, -22)
    panel.intro:SetPoint("RIGHT", -240, 0)
    panel.list = UI.List(panel, CARD_HEIGHT + CARD_GAP, buildCard)
    panel.list:SetPoints(0, -52, 0, 0)
    panel.empty = UI.Label(panel, "GameFontNormal", "CENTER")
    panel.empty:SetPoint("CENTER")
    panel.showHidden = UI.Button(panel, "", 220, O.ResetHidden)
  end,
  Refresh = function(panel)
    local meta = ns.Data.Meta or {}
    local counts = meta.counts or {}
    panel.heading:SetText(L.PROGRESS_HEADING)
    panel.intro:SetText(string.format(L.PROGRESS_INTRO, counts.dungeons or 0, counts.quests or 0, counts.items or 0))
    local objectives, hidden = O.Generate(ns.Compat.Player())
    panel.empty:SetText(#objectives == 0 and L.PROGRESS_EMPTY or "")
    panel.showHidden:SetText(string.format(L.PROGRESS_SHOW_HIDDEN, hidden))
    panel.showHidden:SetShown(hidden > 0)
    panel.showHidden:ClearAllPoints()
    if #objectives > 0 then
      -- Con objetivos visibles, el botón va arriba a la derecha para no tapar la lista.
      panel.showHidden:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -2)
    else
      panel.showHidden:SetPoint("TOP", panel.empty, "BOTTOM", 0, -12)
    end
    panel.list:SetData(objectives, function(row, obj)
      local rgb = CONFIDENCE_RGB[obj.confidence] or CONFIDENCE_RGB.none
      row.bar:SetColorTexture(rgb[1], rgb[2], rgb[3], 0.9)
      row.icon:SetTexture(obj.icon or KIND_ICONS[obj.kind] or KIND_ICONS.info)
      row.title:SetText(obj.title .. (obj.postponed and (" " .. UI.Color("9d9d9d", L.POSTPONED)) or ""))
      row.reason:SetText(table.concat(obj.reasons, " · "))
      row.tag:SetText(UI.Color(UI.CONFIDENCE_COLORS[obj.confidence] or "9d9d9d", L["CONFIDENCE_" .. string.upper(obj.confidence)]))
      row.done:SetText(L.BTN_DONE)
      row.later:SetText(L.BTN_LATER)
      row.dismiss:SetText(L.BTN_DISMISS)
    end)
  end,
})
