-- Generador de objetivos (plan §6.5): una lista corta, ordenada y explicada.
local _, ns = ...

local O = {}
ns.Objectives = O

O.MAX = 6
O.DONE, O.POSTPONED, O.DISMISSED = "done", "postponed", "dismissed"

local function L(key, ...) return string.format(ns.L[key], ...) end

local function dungeonObjectives(player, list)
  local added = 0
  for _, entry in ipairs(ns.Dungeons.Ranked(player)) do
    if added >= 3 or entry.eval.category ~= ns.Dungeons.RECOMMENDED then break end
    local d, eval = entry.dungeon, entry.eval
    local name = ns.Dungeons.Name(d)
    if eval.wing then name = name .. " · " .. ns.Dungeons.WingName(eval.wing) end
    local reasons = { ns.FormatReason(eval.reasons[1]) }
    local journal = ns.Journal.ForInstance(d.instanceID)
    if journal then reasons[#reasons + 1] = L("OBJ_REASON_JOURNAL") end
    added = added + 1
    list[#list + 1] = {
      id = "dungeon:" .. d.instanceID .. (eval.wing and (":" .. eval.wing.id) or ""),
      kind = "dungeon", priority = 10 + added, confidence = eval.confidence,
      title = L("OBJ_DUNGEON", name), reasons = reasons,
      target = { tab = "dungeons", instanceID = d.instanceID },
    }
  end
end

local function gearObjectives(list)
  local weak, average = ns.Gear.WeakSlots(2)
  for i, slot in ipairs(weak) do
    local reason = slot.link and L("OBJ_REASON_GEAR_LOW", slot.itemLevel or 0, average or 0) or L("OBJ_REASON_GEAR_EMPTY")
    list[#list + 1] = {
      id = "gear:" .. slot.key, kind = "gear", priority = 20 + i, confidence = "medium",
      title = L("OBJ_GEAR", ns.L["SLOT_" .. slot.key]), reasons = { reason, L("OBJ_REASON_GEAR_METHOD") },
      target = { tab = "gear" },
    }
  end
end

local function exploreObjectives(list)
  for i, info in ipairs(ns.Journal.Undocumented()) do
    if i > 2 then break end
    list[#list + 1] = {
      id = "explore:" .. info.instanceID, kind = "explore", priority = 30 + i, confidence = "none",
      title = L("OBJ_EXPLORE", info.name), reasons = { L("OBJ_REASON_EXPLORE") },
      target = { tab = "dungeons", instanceID = info.instanceID },
    }
  end
end

local function dataObjectives(list)
  local meta = ns.Data.Meta or {}
  if meta.latestBuildSeen and ns.Compat.CompareBuilds(ns.Compat.ClientBuild(), meta.latestBuildSeen) > 0 then
    list[#list + 1] = {
      id = "data:" .. ns.Compat.ClientBuild(), kind = "info", priority = 50, confidence = "high",
      title = L("OBJ_DATA_STALE"), reasons = { L("OBJ_REASON_DATA_STALE", meta.latestBuildSeen, ns.Compat.ClientBuild()) },
    }
  end
end

function O.Generate(player)
  local all = {}
  dungeonObjectives(player, all)
  ns.Safe("gearObjectives", gearObjectives, all)
  exploreObjectives(all)
  dataObjectives(all)

  local visible = {}
  for _, obj in ipairs(all) do
    local saved = ns.char.objectives[obj.id]
    local state = saved and saved.state
    if state ~= O.DONE and state ~= O.DISMISSED then
      if state == O.POSTPONED then
        obj.postponed = true
        obj.priority = obj.priority + 100
      end
      visible[#visible + 1] = obj
    end
  end
  table.sort(visible, function(a, b) return a.priority < b.priority end)
  while #visible > O.MAX do table.remove(visible) end
  return visible
end

function O.SetState(id, state)
  ns.char.objectives[id] = state and { state = state, at = time(), level = UnitLevel("player") } or nil
  ns.Fire("OBJECTIVES_CHANGED")
end

-- Lo pospuesto vuelve a su sitio al subir de nivel: la situación ha cambiado.
ns.On("PLAYER_LEVEL_UP", function()
  for id, saved in pairs(ns.char.objectives) do
    if saved.state == O.POSTPONED then ns.char.objectives[id] = nil end
  end
  ns.Fire("OBJECTIVES_CHANGED")
end)
