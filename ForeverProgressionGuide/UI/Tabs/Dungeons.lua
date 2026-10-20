-- Pestaña Mazmorras: lista evaluada para el personaje y ficha con
-- información, misiones, botín (con iconos y mejoras) y mapa.
local _, ns = ...

local UI, D, J, I, Q = ns.UI, ns.Dungeons, ns.Journal, ns.Items, ns.Quests
local L = ns.L

local LIST_WIDTH = 250
local ROW_HEIGHT = 24
local selected
local onlyRecommended = false
local onlyUsableLoot = true
local mode = "info"
local MODES = { "info", "quests", "loot", "map" }

local function levelsText(levels)
  return levels and levels.min and (levels.min == levels.max and tostring(levels.min) or (levels.min .. "-" .. levels.max)) or "?"
end

local function factionText(faction)
  return L["FACTION_" .. string.upper(faction or "both")]
end

local function provenanceLine(d)
  local parts = {}
  for _, field in ipairs({ "exists", "levels", "bosses" }) do
    local _, status = D.Confidence(d, field)
    if field == "exists" and not (d.provenance and d.provenance.exists) then status = "unknown" end
    parts[#parts + 1] = L["FIELD_" .. string.upper(field)] .. ": " .. L["STATUS_" .. string.upper(status)]
  end
  return table.concat(parts, " · ")
end

local function infoText(d, eval)
  local lines = {}
  local badges = {}
  if d.isNew then badges[#badges + 1] = UI.Color("ffd100", L.BADGE_NEW) end
  if d.available == false then badges[#badges + 1] = UI.Color("ff5050", L.BADGE_UNAVAILABLE) end
  if #badges > 0 then lines[#lines + 1] = table.concat(badges, "  ") end

  lines[#lines + 1] = UI.Color(UI.CATEGORY_COLORS[eval.category], L["CATEGORY_" .. string.upper(eval.category)])
  for _, reason in ipairs(eval.reasons) do lines[#lines + 1] = "  • " .. ns.FormatReason(reason) end

  if d.entrance then
    lines[#lines + 1] = ""
    lines[#lines + 1] = UI.Color("ffd100", L.DETAIL_ENTRANCE) .. "  " .. ns.Localized(d.entrance)
  end
  local notes = d.notes and ns.Localized(d.notes)
  if notes and #notes > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = UI.Color("ffd100", L.DETAIL_NOTES)
    for _, note in ipairs(notes) do lines[#lines + 1] = "  • " .. note end
  end

  local journal = d.instanceID and J.ForInstance(d.instanceID)
  if journal and journal.description and journal.description ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = journal.description
  end

  local bosses, origin = D.Bosses(d)
  lines[#lines + 1] = ""
  lines[#lines + 1] = UI.Color("ffd100", L.DETAIL_BOSSES) .. "  " .. UI.Color("9d9d9d", L["BOSSES_FROM_" .. string.upper(origin)])
  if #bosses == 0 then lines[#lines + 1] = "  " .. L.DETAIL_NO_BOSSES end
  for i, b in ipairs(bosses) do
    lines[#lines + 1] = string.format("  %d. %s", i, b.name or "?")
  end

  local player = ns.Compat.Player()
  local questCount = #Q.ForDungeon(d, player)
  if d.quests and #d.quests > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(L.DETAIL_QUEST_SUMMARY, questCount, #d.quests)
  end
  if d.loot and #d.loot > 0 then
    lines[#lines + 1] = string.format(L.DETAIL_LOOT_SUMMARY, #d.loot)
  end

  local observed = d.observed or {}
  if observed.levelsSeen then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(L.DETAIL_LEVELS_SEEN, observed.levelsSeen.min, observed.levelsSeen.max)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = UI.Color("9d9d9d", provenanceLine(d))
  return table.concat(lines, "\n")
end

local function renderQuests(panel, d)
  local player = ns.Compat.Player()
  local rows = Q.ListForDungeon(d, player)
  panel.listMessage:SetText(#rows == 0 and L.DUNGEON_NO_QUESTS or L.DUNGEON_QUESTS_HINT)
  panel.list:SetData(rows, function(row, entry)
    local q = entry.quest
    local color = entry.done and "9d9d9d" or (#entry.missing > 0 and "ff9933" or "ffd100")
    local mark = entry.done and (" " .. L.QUEST_DONE) or (#entry.missing > 0 and (" " .. L.QUEST_LOCKED) or "")
    row.icon:SetTexture(entry.done and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\GossipFrame\\AvailableQuestIcon")
    row.left:SetText(UI.Color(color, (q.level and ("[" .. q.level .. "] ") or "") .. Q.Name(q)) .. UI.Color("9d9d9d", mark))
    row.right:SetText(q.xp and string.format(L.QUEST_XP_SHORT, q.xp) or "")
  end)
  panel.list.onEnter = function(entry, row) UI.Tooltip(row, Q.TooltipLines(entry.quest)) end
end

local function renderLoot(panel, d)
  local filter = ns.ClassFilter.Current()
  local player = ns.Compat.Player()
  local loot = I.DungeonLoot(d, filter.classFile or player.class, player.level, onlyUsableLoot)
  local label = string.format(L.LOOT_FOR, ns.ClassFilter.Label(filter))
  panel.listMessage:SetText(#loot == 0 and (label .. " · " .. L.LOOT_EMPTY) or (label .. " · " .. L.LOOT_HINT))
  panel.list:SetData(loot, function(row, entry)
    local item = entry.item or {}
    row.icon:SetTexture(I.Icon(entry.id))
    local fitMark = entry.fit == "best" and "" or UI.Color("9d9d9d", "  (" .. L["FIT_" .. string.upper(entry.fit)] .. ")")
    row.left:SetText(I.ColoredName(entry.id) .. fitMark)
    local right = {}
    if entry.upgrade and entry.upgrade > 0 and entry.fit ~= "no" then right[#right + 1] = UI.Color("40ff40", "+" .. entry.upgrade) end
    if item.ilvl then right[#right + 1] = string.format(L.ITEM_LEVEL_SHORT, item.ilvl) end
    if item.req and item.req > player.level then right[#right + 1] = UI.Color("ff5050", string.format(L.ITEM_REQ_SHORT, item.req)) end
    row.right:SetText(table.concat(right, "  "))
  end)
  panel.list.onEnter = function(entry, row) I.ShowTooltip(row, entry.id) end
end

local function showDetail(panel)
  local d = selected
  local show = d ~= nil
  panel.detail:SetShown(show)
  panel.placeholder:SetShown(not show)
  if not show then return end

  local eval = D.Evaluate(d, ns.Compat.Player())
  panel.name:SetText(D.Name(d))
  local size = d.size and string.format(L.DETAIL_SIZE, d.size) or ""
  panel.meta:SetText(table.concat({ D.ZoneName(d) or "?", L.DETAIL_LEVELS .. " " .. levelsText(d.levels),
                                    factionText(d.faction), size }, " · "))

  local entrance, origin = J.Entrance(d)
  panel.route:SetEnabled(entrance ~= nil and entrance.x ~= nil)
  panel.route.entrance = entrance
  panel.route.origin = origin
  panel.route:SetText(L.BTN_ROUTE)

  for _, m in ipairs(MODES) do
    panel.modes[m]:SetText(L["BTN_" .. string.upper(m)])
    panel.modes[m]:SetEnabled(mode ~= m)
  end

  local isList = mode == "quests" or mode == "loot"
  panel.info.scroll:SetShown(mode == "info")
  panel.map:SetShown(mode == "map")
  panel.list.scroll:SetShown(isList)
  panel.listMessage:SetShown(isList)
  panel.lootFilter:SetShown(mode == "loot")

  if mode == "info" then
    panel.info:SetText(infoText(d, eval))
  elseif mode == "map" then
    panel.map.worldMapButton:SetText(L.MAP_OPEN_WORLD)
    panel.map:ShowDungeon(d)
  elseif mode == "quests" then
    renderQuests(panel, d)
  else
    panel.lootFilter:SetText(onlyUsableLoot and L.LOOT_FILTER_USABLE or L.LOOT_FILTER_ALL)
    renderLoot(panel, d)
  end
end

local function refreshList(panel)
  local player = ns.Compat.Player()
  local rows = {}
  for _, entry in ipairs(D.Ranked(player)) do
    if not onlyRecommended or entry.eval.category == D.RECOMMENDED then rows[#rows + 1] = entry end
  end
  table.sort(rows, function(a, b)
    local la = a.dungeon.levels and a.dungeon.levels.min or 999
    local lb = b.dungeon.levels and b.dungeon.levels.min or 999
    if la ~= lb then return la < lb end
    return D.Name(a.dungeon) < D.Name(b.dungeon)
  end)
  panel.dungeonList:SetData(rows, function(row, entry)
    local d = entry.dungeon
    local suffix = ""
    if d.type == "raid" then suffix = UI.Color("9d9d9d", " · " .. L.RAID) end
    if d.isNew then suffix = suffix .. UI.Color("ffd100", " *") end
    row.left:SetText(UI.Color(UI.CATEGORY_COLORS[entry.eval.category], D.Name(d)) .. suffix)
    row.right:SetText(levelsText(d.levels))
    row.selected:SetShown(d == selected)
  end)
  panel.filter:SetText(onlyRecommended and L.FILTER_RECOMMENDED or L.FILTER_ALL)
end

local function dungeonRow(content, list)
  local row = CreateFrame("Button", nil, content)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(1, 0.82, 0, 0.18)
  row.left = UI.Label(row, "GameFontHighlight")
  row.left:SetPoint("LEFT", 6, 0)
  row.left:SetPoint("RIGHT", -44, 0)
  row.left:SetWordWrap(false)
  row.right = UI.Label(row, "GameFontHighlightSmall", "RIGHT")
  row.right:SetPoint("RIGHT", -6, 0)
  row:SetScript("OnClick", function(self) if list.onClick then list.onClick(self.item) end end)
  return row
end

UI.RegisterTab({
  key = "dungeons",
  Build = function(panel)
    panel.filter = UI.Button(panel, "", LIST_WIDTH - 24, function()
      onlyRecommended = not onlyRecommended
      refreshList(panel)
    end)
    panel.filter:SetPoint("TOPLEFT", 0, 0)

    panel.dungeonList = UI.List(panel, 20, dungeonRow)
    panel.dungeonList.scroll:SetPoint("TOPLEFT", 0, -28)
    panel.dungeonList.scroll:SetPoint("BOTTOMLEFT", 0, 0)
    panel.dungeonList.scroll:SetWidth(LIST_WIDTH - 24)
    panel.dungeonList.onClick = function(entry)
      selected = entry.dungeon
      refreshList(panel)
      showDetail(panel)
    end

    panel.placeholder = UI.Label(panel, "GameFontNormal", "CENTER")
    panel.placeholder:SetPoint("TOPLEFT", LIST_WIDTH + 10, -40)
    panel.placeholder:SetPoint("RIGHT", 0, 0)

    local detail = CreateFrame("Frame", nil, panel)
    detail:SetPoint("TOPLEFT", LIST_WIDTH + 10, 0)
    detail:SetPoint("BOTTOMRIGHT", 0, 0)
    panel.detail = detail

    panel.name = UI.Label(detail, "GameFontNormalLarge")
    panel.name:SetPoint("TOPLEFT", 0, 0)
    panel.meta = UI.Label(detail, "GameFontHighlightSmall")
    panel.meta:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -4)

    panel.modes = {}
    local previous
    for _, m in ipairs(MODES) do
      local b = UI.Button(detail, "", 92, function() mode = m showDetail(panel) end)
      if previous then b:SetPoint("LEFT", previous, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 0, -44) end
      panel.modes[m] = b
      previous = b
    end
    panel.route = UI.Button(detail, "", 110, function(self)
      local e = self.entrance
      if not (e and J.SetWaypoint(e.uiMapID, e.x, e.y)) and e and e.x then
        print(string.format(L.ROUTE_COORDS, e.zone or "?", e.x * 100, e.y * 100))
      end
    end)
    panel.route:SetPoint("LEFT", previous, "RIGHT", 12, 0)
    panel.route:SetScript("OnEnter", function(self)
      UI.Tooltip(self, { L.BTN_ROUTE, self.origin == "observed" and L.ROUTE_OBSERVED or L.ROUTE_JOURNAL })
    end)
    panel.route:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local body = CreateFrame("Frame", nil, detail)
    body:SetPoint("TOPLEFT", 0, -72)
    body:SetPoint("BOTTOMRIGHT", 0, 0)

    panel.info = UI.TextPanel(body)
    panel.info.scroll:SetPoint("TOPLEFT", 0, 0)
    panel.info.scroll:SetPoint("BOTTOMRIGHT", -24, 0)

    panel.map = UI.MapView(body)
    panel.map:SetAllPoints()

    panel.listMessage = UI.Label(body, "GameFontHighlightSmall")
    panel.listMessage:SetPoint("TOPLEFT", 0, -2)
    panel.listMessage:SetPoint("RIGHT", -150, 0)
    panel.lootFilter = UI.Button(body, "", 140, function()
      onlyUsableLoot = not onlyUsableLoot
      showDetail(panel)
    end)
    panel.lootFilter:SetHeight(20)
    panel.lootFilter:SetPoint("TOPRIGHT", 0, 0)
    panel.list = UI.List(body, ROW_HEIGHT, UI.IconRow)
    panel.list:SetPoints(0, -24, 0, 0)
  end,
  Refresh = function(panel, arg)
    if arg and (arg.id or arg.instanceID) then
      selected = D.Get(arg.id or arg.instanceID) or selected
      mode = "info"
    end
    panel.placeholder:SetText(L.DUNGEONS_PICK)
    refreshList(panel)
    showDetail(panel)
  end,
})
