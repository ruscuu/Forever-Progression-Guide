-- Pestaña Buscador: mazmorras, alas y jefes en los dos idiomas.
local _, ns = ...

local UI, D = ns.UI, ns.Dungeons
local L = ns.L

local ICONS = {
  dungeon = "Interface\\LFGFrame\\LFGIcon-Dungeon",
  wing = "Interface\\LFGFrame\\LFGIcon-Dungeon",
  boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  quest = "Interface\\GossipFrame\\AvailableQuestIcon",
}

local function matches(text, query)
  return text and string.find(string.lower(text), query, 1, true) ~= nil
end

local function anyName(names, query)
  if type(names) ~= "table" then return matches(names, query) end
  for _, n in pairs(names) do
    if matches(n, query) then return true end
  end
  return false
end

local MAX_RESULTS = 100

-- Mazmorra donde cae un objeto, para poder abrirla desde el buscador.
local function dungeonDropping(itemId)
  for _, d in pairs(ns.Data.Dungeons or {}) do
    for _, drop in ipairs(d.loot or {}) do
      if drop.itemId == itemId then return d end
    end
  end
end

function ns.Search(query)
  query = string.lower(query or "")
  local results = {}
  if #query < 2 then return results end
  for _, d in ipairs(D.All()) do
    if anyName(d.name, query) or anyName(d.zone, query) then
      results[#results + 1] = { kind = "dungeon", label = D.Name(d), dungeon = d }
    end
    for _, w in ipairs(d.wings or {}) do
      if anyName(w.name, query) then
        results[#results + 1] = { kind = "wing", label = D.WingName(w) .. " · " .. D.Name(d), dungeon = d }
      end
    end
    for _, b in ipairs(d.bosses or {}) do
      if anyName(b.name, query) then
        results[#results + 1] = { kind = "boss", label = ns.Localized(b.name) .. " · " .. D.Name(d), dungeon = d }
      end
    end
  end
  for id, q in pairs(ns.Data.Quests or {}) do
    if #results >= MAX_RESULTS then break end
    if anyName(q.name, query) or matches(ns.Quests.Name(q), query) then
      local d = q.dungeon and D.Get(q.dungeon)
      results[#results + 1] = { kind = "quest", label = ns.Quests.Name(q) .. (d and (" · " .. D.Name(d)) or ""), dungeon = d, questId = id }
    end
  end
  for id, item in pairs(ns.Data.Items or {}) do
    if #results >= MAX_RESULTS then break end
    if matches(item.name, query) or matches(ns.Items.Name(id), query) then
      local d = dungeonDropping(id)
      results[#results + 1] = { kind = "item", label = ns.Items.ColoredName(id) .. (d and (" · " .. D.Name(d)) or ""), dungeon = d, itemId = id }
    end
  end
  return results
end

UI.RegisterTab({
  key = "search",
  Build = function(panel)
    panel.box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.box:SetSize(260, 22)
    panel.box:SetPoint("TOPLEFT", 6, -4)
    panel.box:SetAutoFocus(false)
    panel.hint = UI.Label(panel, "GameFontHighlightSmall")
    panel.hint:SetPoint("LEFT", panel.box, "RIGHT", 10, 0)
    panel.list = UI.List(panel, 22, UI.IconRow)
    panel.list:SetPoints(0, -34, 0, 0)
    panel.list.onClick = function(r) if r.dungeon then UI.Select("dungeons", { id = r.dungeon.id }) end end
    panel.list.onEnter = function(r, row)
      if r.itemId then ns.Items.ShowTooltip(row, r.itemId)
      elseif r.questId then UI.Tooltip(row, ns.Quests.TooltipLines(ns.Quests.Get(r.questId))) end
    end
    local function update()
      local results = ns.Search(panel.box:GetText())
      panel.list:SetData(results, function(row, r)
        row.icon:SetTexture(r.itemId and ns.Items.Icon(r.itemId) or ICONS[r.kind])
        row.left:SetText(UI.Color("9d9d9d", "[" .. L["KIND_" .. string.upper(r.kind)] .. "] ") .. r.label)
        row.right:SetText("")
      end)
    end
    panel.box:SetScript("OnTextChanged", update)
    panel.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.update = update
  end,
  Refresh = function(panel)
    panel.hint:SetText(L.SEARCH_HINT)
    panel.update()
  end,
})
