-- Pestaña Misiones: misiones de mazmorra y de élite disponibles para tu nivel
-- (datos de Forever Companion) y tu registro de misiones actual.
local _, ns = ...

local UI, C, Q = ns.UI, ns.Compat, ns.Quests
local L = ns.L

local mode = "available"

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

local function renderAvailable(panel)
  local player = C.Player()
  local quests = Q.ForLevel(player)
  panel.intro:SetText(string.format(L.QUESTS_AVAILABLE_INTRO, #quests))
  panel.list:SetData(quests, function(row, q)
    local locked = #Q.MissingPrereqs(q) > 0
    row.icon:SetTexture(q.type == "dungeon" and "Interface\\LFGFrame\\LFGIcon-Dungeon" or "Interface\\GossipFrame\\AvailableQuestIcon")
    local where = q.dungeon and ns.Dungeons.Get(q.dungeon)
    local place = where and ns.Dungeons.Name(where) or q.zone or ""
    row.left:SetText(UI.Color(levelColor(q.level), (q.level and ("[" .. q.level .. "] ") or "") .. Q.Name(q))
      .. UI.Color("9d9d9d", "  " .. place .. (locked and ("  " .. L.QUEST_LOCKED) or "")))
    row.right:SetText(q.xp and string.format(L.QUEST_XP_SHORT, q.xp) or "")
  end)
  panel.list.onEnter = function(q, row) UI.Tooltip(row, Q.TooltipLines(q)) end
  panel.list.onClick = function(q) if q.dungeon then UI.Select("dungeons", { id = q.dungeon }) end end
end

local function renderLog(panel)
  local _, observed = ns.Collector.Summary()
  panel.intro:SetText(string.format(L.QUESTS_INTRO, observed))
  panel.list:SetData(questLog(), function(row, q)
    row.icon:SetTexture(q.isHeader and nil or "Interface\\GossipFrame\\ActiveQuestIcon")
    if q.isHeader then
      row.left:SetText(UI.Color("ffd100", q.title))
      row.right:SetText("")
    else
      row.left:SetText(UI.Color(levelColor(q.level), (q.level and ("[" .. q.level .. "] ") or "") .. q.title))
      row.right:SetText(q.questID and ("#" .. q.questID) or "")
    end
  end)
  panel.list.onEnter = function(q, row)
    local data = q.questID and Q.Get(q.questID)
    if data then UI.Tooltip(row, Q.TooltipLines(data)) end
  end
  panel.list.onClick = nil
end

UI.RegisterTab({
  key = "quests",
  Build = function(panel)
    panel.available = UI.Button(panel, "", 160, function() mode = "available" UI.Select("quests") end)
    panel.available:SetPoint("TOPLEFT", 0, 0)
    panel.log = UI.Button(panel, "", 160, function() mode = "log" UI.Select("quests") end)
    panel.log:SetPoint("LEFT", panel.available, "RIGHT", 4, 0)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, -28)
    panel.intro:SetPoint("RIGHT", 0, 0)
    panel.list = UI.List(panel, 22, UI.IconRow)
    panel.list:SetPoints(0, -60, 0, 0)
  end,
  Refresh = function(panel)
    panel.available:SetText(L.QUESTS_MODE_AVAILABLE)
    panel.log:SetText(L.QUESTS_MODE_LOG)
    panel.available:SetEnabled(mode ~= "available")
    panel.log:SetEnabled(mode ~= "log")
    if mode == "available" then renderAvailable(panel) else renderLog(panel) end
  end,
})
