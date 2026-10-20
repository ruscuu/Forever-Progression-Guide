-- Pestaña Progresión: próximos objetivos con su explicación.
local _, ns = ...

local UI, O = ns.UI, ns.Objectives
local L = ns.L

local ROW_HEIGHT = 58

local function buildRow(content, list)
  local row = CreateFrame("Button", nil, content)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.title = UI.Label(row, "GameFontNormal")
  row.title:SetPoint("TOPLEFT", 6, -6)
  row.title:SetPoint("RIGHT", -190, 0)
  row.title:SetWordWrap(false)
  row.reason = UI.Label(row, "GameFontHighlightSmall")
  row.reason:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
  row.reason:SetPoint("RIGHT", -190, 0)
  row.reason:SetHeight(28)

  local function action(state)
    return function() O.SetState(row.item.id, state) end
  end
  row.done = UI.Button(row, "", 60, action(O.DONE))
  row.later = UI.Button(row, "", 60, action(O.POSTPONED))
  row.dismiss = UI.Button(row, "", 60, action(O.DISMISSED))
  for i, b in ipairs({ row.done, row.later, row.dismiss }) do
    b:SetHeight(20)
    b:SetPoint("TOPRIGHT", -(3 - i) * 62 - 4, -8)
  end
  row:SetScript("OnClick", function(self)
    if self.item.target then UI.Select(self.item.target.tab, self.item.target) end
  end)
  return row
end

UI.RegisterTab({
  key = "progress",
  Build = function(panel)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, 0)
    panel.intro:SetPoint("RIGHT", 0, 0)
    panel.list = UI.List(panel, ROW_HEIGHT, buildRow)
    panel.list:SetPoints(0, -34, 0, 0)
    panel.empty = UI.Label(panel, "GameFontNormal", "CENTER")
    panel.empty:SetPoint("CENTER")
  end,
  Refresh = function(panel)
    local meta = ns.Data.Meta or {}
    local counts = meta.statusCounts or {}
    panel.intro:SetText(string.format(L.PROGRESS_INTRO, (meta.counts or {}).dungeons or 0, counts.verified_ingame or 0))
    local objectives = O.Generate(ns.Compat.Player())
    panel.empty:SetText(#objectives == 0 and L.PROGRESS_EMPTY or "")
    panel.list:SetData(objectives, function(row, obj)
      local tag = UI.Color(UI.CONFIDENCE_COLORS[obj.confidence] or "9d9d9d", L["CONFIDENCE_" .. string.upper(obj.confidence)])
      row.title:SetText(obj.title .. (obj.postponed and (" " .. UI.Color("9d9d9d", L.POSTPONED)) or ""))
      row.reason:SetText(table.concat(obj.reasons, " · ") .. "  " .. tag)
      row.done:SetText(L.BTN_DONE)
      row.later:SetText(L.BTN_LATER)
      row.dismiss:SetText(L.BTN_DISMISS)
    end)
  end,
})
