-- Observaciones hechas mientras juegas: instancias, mapas, entradas, jefes y
-- misiones. Se guardan en SavedVariables y pipeline/import_contributions.py las
-- convierte en datos `verified_ingame`. No se guarda ningún dato personal.
local _, ns = ...

local C = ns.Compat
local Collector = {}
ns.Collector = Collector

local lastOutdoor
local currentInstance

local function store()
  return ns.db and ns.db.settings.collect and ns.db.contributions
end

local function playerPosition()
  local mapID = C.Call("C_Map.GetBestMapForUnit", "player")
  if not mapID then return nil end
  local pos = C.Call("C_Map.GetPlayerMapPosition", mapID, "player")
  if not pos then return { mapID = mapID } end
  local x, y = pos:GetXY()
  return { mapID = mapID, x = x and math.floor(x * 10000 + 0.5) / 10000, y = y and math.floor(y * 10000 + 0.5) / 10000 }
end

local function instanceRecord(contrib, instanceID)
  contrib.instances[instanceID] = contrib.instances[instanceID] or { uiMapIDs = {}, levels = {}, encounters = {} }
  return contrib.instances[instanceID]
end

function Collector.Update(entering)
  local contrib = store()
  if not contrib then return end
  local inInstance, instanceType = IsInInstance()
  if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
    currentInstance = nil
    lastOutdoor = playerPosition() or lastOutdoor
    return
  end

  local name, _, _, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
  if not instanceID then return end
  local rec = instanceRecord(contrib, instanceID)
  rec.name, rec.type, rec.maxPlayers, rec.locale = name, instanceType, maxPlayers, GetLocale()
  rec.lastSeen = time()
  rec.firstSeen = rec.firstSeen or rec.lastSeen
  contrib.builds[C.ClientBuild()] = true

  local mapID = C.Call("C_Map.GetBestMapForUnit", "player")
  if mapID then rec.uiMapIDs[mapID] = true end

  if currentInstance ~= instanceID then
    currentInstance = instanceID
    local level = UnitLevel("player")
    rec.levels[level] = (rec.levels[level] or 0) + 1
    -- La última posición en exteriores antes de entrar es una buena aproximación de la entrada.
    if not rec.entrance and lastOutdoor and lastOutdoor.x then rec.entrance = lastOutdoor end
  end
  if entering then ns.Fire("INSTANCE_OBSERVED", instanceID) end
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
  ns.On(event, function() Collector.Update(false) end)
end
ns.On("PLAYER_ENTERING_WORLD", function() Collector.Update(true) end)

ns.On("ENCOUNTER_END", function(encounterID, encounterName, _, _, success)
  local contrib = store()
  if not contrib or success ~= 1 or not currentInstance then return end
  local rec = instanceRecord(contrib, currentInstance)
  local enc = rec.encounters[encounterID] or { name = encounterName, kills = 0 }
  enc.kills = enc.kills + 1
  rec.encounters[encounterID] = enc
end)

local function questRecord(questID)
  local contrib = store()
  if not contrib or not questID then return nil end
  contrib.quests[questID] = contrib.quests[questID] or {}
  return contrib.quests[questID]
end

-- En clientes modernos el evento trae (questID); en los clásicos, (índice, questID).
ns.On("QUEST_ACCEPTED", function(a, b)
  local rec = questRecord(b or a)
  if not rec then return end
  local index = C.Call("C_QuestLog.GetLogIndexForQuestID", b or a)
  local info = index and C.Call("C_QuestLog.GetInfo", index)
  rec.level = info and info.level or rec.level
  rec.mapID = C.Call("C_Map.GetBestMapForUnit", "player") or rec.mapID
  rec.accepted = (rec.accepted or 0) + 1
end)

ns.On("QUEST_TURNED_IN", function(questID, xpReward)
  local rec = questRecord(questID)
  if not rec then return end
  rec.xp = xpReward or rec.xp
  rec.turnedIn = (rec.turnedIn or 0) + 1
end)

function Collector.Summary()
  local contrib = ns.db and ns.db.contributions or { instances = {}, quests = {} }
  local instances, quests = 0, 0
  for _ in pairs(contrib.instances) do instances = instances + 1 end
  for _ in pairs(contrib.quests) do quests = quests + 1 end
  return instances, quests
end
