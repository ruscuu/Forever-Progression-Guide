-- Misiones de mazmorra y de élite (Forever Companion): cuáles puede hacer el
-- personaje, cuáles ya hizo y qué cadena de requisitos tienen.
local _, ns = ...

local C = ns.Compat
local Q = {}
ns.Quests = Q

-- Niveles por encima del tuyo que todavía se consideran «para ti».
Q.LEVEL_MARGIN = 4

function Q.Get(id) return ns.Data.Quests and ns.Data.Quests[id] end

local requested = {}

function Q.Name(q)
  local title = C.Call("C_QuestLog.GetTitleForQuestID", q.id)
  if not title and not requested[q.id] then
    requested[q.id] = true
    C.Call("C_QuestLog.RequestLoadQuestByID", q.id)
  end
  return ns.PickName(title, q.name) or ("#" .. q.id)
end

function Q.IsDone(id)
  return C.Call("C_QuestLog.IsQuestFlaggedCompleted", id) or C.Call("IsQuestFlaggedCompleted", id) or false
end

local function classAllowed(q, classFile)
  if not q.classes then return true end
  for _, c in ipairs(q.classes) do
    if string.upper(c) == classFile then return true end
  end
  return false
end

-- ¿La puede hacer este personaje? (facción, clase y nivel mínimo)
function Q.Available(q, player)
  if q.faction and q.faction ~= "both" and q.faction ~= player.faction then return false end
  if not classAllowed(q, player.class) then return false end
  return (q.minLevel or 1) <= player.level
end

-- Requisitos sin hacer, en orden.
function Q.MissingPrereqs(q)
  local missing = {}
  for _, step in ipairs(q.prereqs or {}) do
    for _, id in ipairs(step) do
      if not Q.IsDone(id) then missing[#missing + 1] = id end
    end
  end
  return missing
end

-- Misiones de una mazmorra que el personaje puede llevar, sin las ya hechas.
function Q.ForDungeon(d, player)
  local out = {}
  for _, id in ipairs(d.quests or {}) do
    local q = Q.Get(id)
    if q and Q.Available(q, player) and not Q.IsDone(id) then out[#out + 1] = q end
  end
  return out
end

-- Todas las misiones de la mazmorra para mostrar, con su estado.
function Q.ListForDungeon(d, player)
  local out = {}
  for _, id in ipairs(d.quests or {}) do
    local q = Q.Get(id)
    if q and (not q.faction or q.faction == "both" or q.faction == player.faction) and classAllowed(q, player.class) then
      out[#out + 1] = { quest = q, done = Q.IsDone(id), missing = Q.MissingPrereqs(q) }
    end
  end
  table.sort(out, function(a, b) return (a.quest.level or 0) < (b.quest.level or 0) end)
  return out
end

-- Misiones de élite y de mazmorra apropiadas para el nivel, no hechas.
function Q.ForLevel(player)
  local out = {}
  for id, q in pairs(ns.Data.Quests or {}) do
    if Q.Available(q, player) and (q.level or 0) <= player.level + Q.LEVEL_MARGIN and not Q.IsDone(id) then
      out[#out + 1] = q
    end
  end
  table.sort(out, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    return a.id < b.id
  end)
  return out
end

-- Texto para el tooltip de una misión.
function Q.TooltipLines(q)
  local L = ns.L
  local lines = { Q.Name(q) }
  if q.level then lines[#lines + 1] = string.format(L.QUEST_LEVEL, q.level, q.minLevel or q.level) end
  if q.giver then lines[#lines + 1] = string.format(L.QUEST_GIVER, q.giver, q.location or "?") end
  if q.objective then lines[#lines + 1] = q.objective end
  if q.xp then lines[#lines + 1] = string.format(q.xpEstimated and L.QUEST_XP_ESTIMATED or L.QUEST_XP, q.xp) end
  if q.rewards then
    local names = {}
    for _, id in ipairs(q.rewards) do names[#names + 1] = ns.Items.ColoredName(id) end
    lines[#lines + 1] = (q.rewardChoice and L.QUEST_REWARD_CHOICE or L.QUEST_REWARD) .. " " .. table.concat(names, ", ")
  end
  local missing = Q.MissingPrereqs(q)
  if #missing > 0 then
    local names = {}
    for _, id in ipairs(missing) do
      local pre = Q.Get(id)
      names[#names + 1] = pre and Q.Name(pre) or ("#" .. id)
    end
    lines[#lines + 1] = "|cffff9933" .. L.QUEST_PREREQS .. " " .. table.concat(names, " → ") .. "|r"
  end
  lines[#lines + 1] = "|cff9d9d9d" .. L["STATUS_" .. string.upper(q.status or "unknown")] .. "|r"
  return lines
end
