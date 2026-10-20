-- Pestaña Misiones: registro de misiones actual. Las cadenas y requisitos
-- (plan §6.3) llegarán cuando haya una fuente de misiones confirmada.
local _, ns = ...

local UI, C = ns.UI, ns.Compat
local L = ns.L

local function questLog()
  local out = {}
  if C.Has("C_QuestLog.GetNumQuestLogEntries") and C.Has("C_QuestLog.GetInfo") then
    for i = 1, C.Call("C_QuestLog.GetNumQuestLogEntries") or 0 do
      local info = C.Call("C_QuestLog.GetInfo", i)
      if info then out[#out + 1] = { title = info.title, level = info.level, questID = info.questID, isHeader = info.isHeader } end
    end
  elseif C.Has("GetQuestLogTitle") then
    for i = 1, (C.Call("GetNumQuestLogEntries")) or 0 do
      local title, level, _, isHeader, _, _, _, questID = C.Call("GetQuestLogTitle", i)
      if title then out[#out + 1] = { title = title, level = level, questID = questID, isHeader = isHeader } end
    end
  end
  return out
end

local function levelColor(level)
  local c = level and C.Call("GetQuestDifficultyColor", level)
  if type(c) ~= "table" then return "ffffff" end
  return string.format("%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
end

UI.RegisterTab({
  key = "quests",
  Build = function(panel)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, 0)
    panel.intro:SetPoint("RIGHT", 0, 0)
    panel.list = UI.List(panel, 20)
    panel.list:SetPoints(0, -60, 0, 0)
  end,
  Refresh = function(panel)
    local _, observed = ns.Collector.Summary()
    panel.intro:SetText(string.format(L.QUESTS_INTRO, observed))
    panel.list:SetData(questLog(), function(row, q)
      if q.isHeader then
        row.left:SetText(UI.Color("ffd100", q.title))
        row.right:SetText("")
      else
        row.left:SetText("   " .. UI.Color(levelColor(q.level), (q.level and ("[" .. q.level .. "] ") or "") .. q.title))
        row.right:SetText(q.questID and ("#" .. q.questID) or "")
      end
    end)
  end,
})
