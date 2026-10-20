-- Pestaña Mazmorras: lista evaluada para el personaje y ficha con información,
-- mapa, botín de la clase y cómo llegar.
local _, ns = ...

local UI, D, J = ns.UI, ns.Dungeons, ns.Journal
local L = ns.L

local LIST_WIDTH = 250
local selected
local onlyRecommended = false
local mode = "info"

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
  lines[#lines + 1] = UI.Color(UI.CATEGORY_COLORS[eval.category], L["CATEGORY_" .. string.upper(eval.category)])
  for _, reason in ipairs(eval.reasons) do lines[#lines + 1] = "  • " .. ns.FormatReason(reason) end
  lines[#lines + 1] = ""
  lines[#lines + 1] = UI.Color("9d9d9d", provenanceLine(d))

  local journal = J.ForInstance(d.instanceID)
  if journal and journal.description and journal.description ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = journal.description
  end

  if d.wings and #d.wings > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = UI.Color("ffd100", L.DETAIL_WINGS)
    for _, w in ipairs(d.wings) do
      lines[#lines + 1] = "  • " .. D.WingName(w) .. "  (" .. levelsText(w.levels) .. ")"
    end
  end

  local bosses, origin = D.Bosses(d)
  lines[#lines + 1] = ""
  lines[#lines + 1] = UI.Color("ffd100", L.DETAIL_BOSSES) .. "  " .. UI.Color("9d9d9d", L["BOSSES_FROM_" .. string.upper(origin)])
  if #bosses == 0 then lines[#lines + 1] = "  " .. L.DETAIL_NO_BOSSES end
  local wingNames = {}
  for _, w in ipairs(d.wings or {}) do wingNames[w.id] = D.WingName(w) end
  for i, b in ipairs(bosses) do
    local wing = b.wing and wingNames[b.wing]
    lines[#lines + 1] = string.format("  %d. %s%s", i, b.name or "?", wing and UI.Color("9d9d9d", "  · " .. wing) or "")
  end

  local observed = d.observed or {}
  if observed.levelsSeen then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(L.DETAIL_LEVELS_SEEN, observed.levelsSeen.min, observed.levelsSeen.max)
  end
  return table.concat(lines, "\n")
end

local function lootRows(panel, d)
  local journal = J.ForInstance(d.instanceID)
  local filter = ns.ClassFilter.Current()
  local loot = journal and J.Loot(journal.journalID, filter.classID, filter.specID)
  if not loot then
    panel.lootMessage:SetText(L.LOOT_UNAVAILABLE)
    panel.loot:SetData({}, function() end)
    return
  end
  local label = string.format(L.LOOT_FOR, ns.ClassFilter.Label(filter))
  panel.lootMessage:SetText(#loot == 0 and (label .. " · " .. L.LOOT_EMPTY) or label)
  panel.loot:SetData(loot, function(row, item)
    row.left:SetText(item.link or item.name or ("#" .. item.itemID))
    row.right:SetText(item.slot or "")
  end)
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

  panel.modeInfo:SetText(L.BTN_INFO)
  panel.modeMap:SetText(L.BTN_MAP)
  panel.modeLoot:SetText(L.BTN_LOOT)
  panel.route:SetText(L.BTN_ROUTE)
  panel.modeInfo:SetEnabled(mode ~= "info")
  panel.modeMap:SetEnabled(mode ~= "map")
  panel.modeLoot:SetEnabled(mode ~= "loot")

  panel.info.scroll:SetShown(mode == "info")
  panel.map:SetShown(mode == "map")
  panel.loot.scroll:SetShown(mode == "loot")
  panel.lootMessage:SetShown(mode == "loot")

  if mode == "info" then
    panel.info:SetText(infoText(d, eval))
  elseif mode == "map" then
    panel.map.worldMapButton:SetText(L.MAP_OPEN_WORLD)
    panel.map:ShowDungeon(d)
  else
    lootRows(panel, d)
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
  panel.list:SetData(rows, function(row, entry)
    local d = entry.dungeon
    local name = D.Name(d) .. (d.type == "raid" and UI.Color("9d9d9d", " · " .. L.RAID) or "")
    row.left:SetText(UI.Color(UI.CATEGORY_COLORS[entry.eval.category], name))
    row.right:SetText(levelsText(d.levels))
  end)
  panel.filter:SetText(onlyRecommended and L.FILTER_RECOMMENDED or L.FILTER_ALL)
end

UI.RegisterTab({
  key = "dungeons",
  Build = function(panel)
    panel.filter = UI.Button(panel, "", LIST_WIDTH - 24, function()
      onlyRecommended = not onlyRecommended
      refreshList(panel)
    end)
    panel.filter:SetPoint("TOPLEFT", 0, 0)

    panel.list = UI.List(panel, 20)
    panel.list.scroll:SetPoint("TOPLEFT", 0, -28)
    panel.list.scroll:SetPoint("BOTTOMLEFT", 0, 0)
    panel.list.scroll:SetWidth(LIST_WIDTH - 24)
    panel.list.onClick = function(entry)
      selected = entry.dungeon
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

    local function setMode(m) return function() mode = m showDetail(panel) end end
    panel.modeInfo = UI.Button(detail, "", 100, setMode("info"))
    panel.modeMap = UI.Button(detail, "", 100, setMode("map"))
    panel.modeLoot = UI.Button(detail, "", 100, setMode("loot"))
    panel.route = UI.Button(detail, "", 120, function(self)
      local e = self.entrance
      if not (e and J.SetWaypoint(e.uiMapID, e.x, e.y)) and e and e.x then
        print(string.format(L.ROUTE_COORDS, e.zone or "?", e.x * 100, e.y * 100))
      end
    end)
    panel.route:SetScript("OnEnter", function(self)
      UI.Tooltip(self, { L.BTN_ROUTE, self.origin == "observed" and L.ROUTE_OBSERVED or L.ROUTE_JOURNAL })
    end)
    panel.route:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.modeInfo:SetPoint("TOPLEFT", 0, -44)
    panel.modeMap:SetPoint("LEFT", panel.modeInfo, "RIGHT", 4, 0)
    panel.modeLoot:SetPoint("LEFT", panel.modeMap, "RIGHT", 4, 0)
    panel.route:SetPoint("LEFT", panel.modeLoot, "RIGHT", 12, 0)

    local body = CreateFrame("Frame", nil, detail)
    body:SetPoint("TOPLEFT", 0, -72)
    body:SetPoint("BOTTOMRIGHT", 0, 0)

    panel.info = UI.TextPanel(body)
    panel.info.scroll:SetPoint("TOPLEFT", 0, 0)
    panel.info.scroll:SetPoint("BOTTOMRIGHT", -24, 0)

    panel.map = UI.MapView(body)
    panel.map:SetAllPoints()

    panel.lootMessage = UI.Label(body, "GameFontHighlightSmall")
    panel.lootMessage:SetPoint("TOPLEFT", 0, 0)
    panel.lootMessage:SetPoint("RIGHT", 0, 0)
    panel.loot = UI.List(body, 20)
    panel.loot:SetPoints(0, -18, 0, 0)
    panel.loot.onEnter = function(item, row) if item.link then UI.Tooltip(row, nil, item.link) end end
  end,
  Refresh = function(panel, arg)
    if arg and arg.instanceID then
      selected = D.Get(arg.instanceID) or selected
      mode = "info"
    end
    panel.placeholder:SetText(L.DUNGEONS_PICK)
    refreshList(panel)
    showDetail(panel)
  end,
})
