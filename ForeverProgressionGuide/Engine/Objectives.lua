-- Generador de objetivos (plan §6.5): una lista corta, ordenada y explicada.
local _, ns = ...

local O = {}
ns.Objectives = O

O.MAX = 8
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
    local questCount = #ns.Quests.ForDungeon(d, player)
    if questCount > 0 then reasons[#reasons + 1] = L("OBJ_REASON_DUNGEON_QUESTS", questCount) end
    added = added + 1
    list[#list + 1] = {
      id = "dungeon:" .. d.id .. (eval.wing and (":" .. eval.wing.id) or ""),
      kind = "dungeon", priority = 10 + added, confidence = eval.confidence,
      title = L("OBJ_DUNGEON", name), reasons = reasons,
      target = { tab = "dungeons", id = d.id },
    }
  end
  if added > 0 then return end

  -- Ninguna mazmorra para tu nivel todavía (típico en los primeros niveles):
  -- la próxima que podrás hacer, para que la guía siempre indique un rumbo.
  local nextEntry
  for _, entry in ipairs(ns.Dungeons.Ranked(player)) do
    local d, eval = entry.dungeon, entry.eval
    local ownFaction = not d.faction or d.faction == "both" or d.faction == player.faction
    if eval.category == ns.Dungeons.TOO_EARLY and ownFaction and eval.levels
        and (not nextEntry or eval.levels.min < nextEntry.eval.levels.min) then
      nextEntry = entry
    end
  end
  if not nextEntry then return end
  local d, eval = nextEntry.dungeon, nextEntry.eval
  local from = eval.levels.min - ns.Dungeons.EARLY_MARGIN
  list[#list + 1] = {
    id = "next:" .. d.id, kind = "next", priority = 15, confidence = eval.confidence,
    title = L("OBJ_NEXT_DUNGEON", ns.Dungeons.Name(d)),
    reasons = { L("OBJ_REASON_NEXT", from, from - player.level) },
    target = { tab = "dungeons", id = d.id },
  }
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

-- La mejor mejora que ya llevas en las bolsas: el objetivo más fácil de cumplir.
local function bagObjective(player, list)
  local selection = ns.ClassFilter.Current()
  local role = selection.isPlayer and selection.role or nil
  for _, u in ipairs(ns.Compare.BagUpgrades(player.class, role, player.level)) do
    if not u.future then
      list[#list + 1] = {
        id = "bag:" .. tostring(u.itemID), kind = "bag", priority = 12, confidence = "medium", icon = u.icon,
        title = L("OBJ_BAG_UPGRADE", u.link), reasons = { ns.Compare.DiffText(u.diffs, 3) },
        target = { tab = "gear" },
      }
      return
    end
  end
end

local function factionOk(entry, player)
  return not entry.faction or entry.faction == "both" or entry.faction == player.faction
end

-- Misiones de clase recién disponibles: las esenciales desbloquean habilidades.
local function classQuestObjectives(player, list)
  local found = {}
  for _, cq in pairs(ns.Data.ClassQuests or {}) do
    if cq.class == player.class and cq.level <= player.level and cq.level >= player.level - 6 and factionOk(cq, player) then
      found[#found + 1] = cq
    end
  end
  table.sort(found, function(a, b)
    if a.essential ~= b.essential then return a.essential end
    return a.level > b.level
  end)
  for i, cq in ipairs(found) do
    if i > 2 then break end
    list[#list + 1] = {
      id = "class:" .. cq.id, kind = "class", priority = cq.essential and 16 or 26, confidence = "medium",
      title = L("OBJ_CLASS_QUEST", cq.reward or cq.name),
      reasons = { L("OBJ_REASON_CLASS_QUEST", cq.name, cq.giver or "?", cq.location or "?") },
    }
  end
end

-- Zona de misiones para el nivel: la de mínimo más alto que ya alcanzas.
local function zoneObjective(player, list)
  local best
  for _, z in pairs(ns.Data.Zones or {}) do
    if factionOk(z, player) and not z.race and z.levels.min <= player.level and player.level <= z.levels.max
        and (not best or z.levels.min > best.levels.min) then
      best = z
    end
  end
  if not best then return end
  list[#list + 1] = {
    id = "zone:" .. best.id .. ":" .. player.level, kind = "zone", priority = 40, confidence = "medium",
    title = L("OBJ_ZONE", ns.Localized(best.name)),
    reasons = { L("OBJ_REASON_ZONE", best.levels.min, best.levels.max) },
  }
end

local function exploreObjectives(list)
  for i, info in ipairs(ns.Journal.Undocumented()) do
    if i > 2 then break end
    list[#list + 1] = {
      id = "explore:" .. info.instanceID, kind = "explore", priority = 30 + i, confidence = "none",
      title = L("OBJ_EXPLORE", info.name), reasons = { L("OBJ_REASON_EXPLORE") },
      target = { tab = "dungeons", id = "journal-" .. info.instanceID },
    }
  end
end

local function dataObjectives(list)
  local meta = ns.Data.Meta or {}
  if meta.latestBuildSeen and ns.Compat.CompareBuilds(ns.Compat.ClientBuild(), meta.latestBuildSeen) > 0 then
    list[#list + 1] = {
      id = "data:" .. ns.Compat.ClientBuild(), kind = "info", priority = 5, confidence = "high",
      title = L("OBJ_DATA_STALE"), reasons = { L("OBJ_REASON_DATA_STALE", meta.latestBuildSeen, ns.Compat.ClientBuild()) },
    }
  end
end

function O.Generate(player)
  local all = {}
  dungeonObjectives(player, all)
  ns.Safe("gearObjectives", gearObjectives, all)
  ns.Safe("bagObjective", bagObjective, player, all)
  classQuestObjectives(player, all)
  zoneObjective(player, all)
  exploreObjectives(all)
  dataObjectives(all)

  local visible, hidden = {}, 0
  for _, obj in ipairs(all) do
    local saved = ns.char.objectives[obj.id]
    local state = saved and saved.state
    if state == O.DONE or state == O.DISMISSED then
      hidden = hidden + 1
    else
      if state == O.POSTPONED then
        obj.postponed = true
        obj.priority = obj.priority + 100
      end
      visible[#visible + 1] = obj
    end
  end
  table.sort(visible, function(a, b) return a.priority < b.priority end)
  while #visible > O.MAX do table.remove(visible) end
  -- Segundo valor: objetivos marcados como hechos u ocultos, para poder recuperarlos.
  return visible, hidden
end

function O.ResetHidden()
  ns.char.objectives = {}
  ns.Fire("OBJECTIVES_CHANGED")
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
