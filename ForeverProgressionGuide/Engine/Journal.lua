-- Datos que el propio cliente conoce: diario de mazmorras, mapas de instancia,
-- posición de jefes, entradas en el mapa del mundo y botín por clase.
-- Al leerlos en tiempo real están al día con cada parche sin actualizar el addon.
local _, ns = ...

local C = ns.Compat
local J = {}
ns.Journal = J

local instances      -- [instanceID] = { journalID, name, description, uiMapID, isRaid }
local dungeonMaps    -- [nombre normalizado] = uiMapID
local entrances      -- [journalID] = { uiMapID, x, y, name }

function J.Available()
  return C.Has("EJ_GetInstanceByIndex") and C.Has("EJ_SelectTier")
end

local function scanInstances()
  instances = {}
  if not J.Available() then return end
  local previousTier = C.Call("EJ_GetCurrentTier")
  local tiers = C.Call("EJ_GetNumTiers") or 1
  for tier = 1, tiers do
    C.Call("EJ_SelectTier", tier)
    for _, isRaid in ipairs({ false, true }) do
      local index = 1
      while true do
        local journalID, name, description, _, _, _, _, uiMapID, _, _, instanceID =
          C.Call("EJ_GetInstanceByIndex", index, isRaid)
        if not journalID then break end
        if instanceID and not instances[instanceID] then
          instances[instanceID] = { journalID = journalID, name = name, description = description,
                                    uiMapID = uiMapID ~= 0 and uiMapID or nil, isRaid = isRaid, instanceID = instanceID }
        end
        index = index + 1
      end
    end
  end
  if previousTier then C.Call("EJ_SelectTier", previousTier) end
end

function J.ForInstance(instanceID)
  if not instances then scanInstances() end
  return instances[instanceID]
end

-- Instancias del diario que no figuran en los datos incluidos (contenido nuevo).
function J.Undocumented()
  if not instances then scanInstances() end
  local out = {}
  for instanceID, info in pairs(instances) do
    if not ns.Dungeons.HasInstance(instanceID) then out[#out + 1] = info end
  end
  table.sort(out, function(a, b) return a.instanceID < b.instanceID end)
  return out
end

function J.Encounters(journalID)
  local out = {}
  local index = 1
  while true do
    local name, _, journalEncounterID, _, _, _, dungeonEncounterID = C.Call("EJ_GetEncounterInfoByIndex", index, journalID)
    if not name then break end
    out[#out + 1] = { name = name, journalEncounterID = journalEncounterID, dungeonEncounterID = dungeonEncounterID }
    index = index + 1
  end
  return out
end

-- Nombre sin artículo inicial ni mayúsculas, para comparar nombres de mapas.
local function normalize(name)
  name = string.lower(name or "")
  for _, article in ipairs({ "the ", "las ", "los ", "la ", "el " }) do
    if string.sub(name, 1, #article) == article then return string.sub(name, #article + 1) end
  end
  return name
end

-- Mapas de mazmorra que conoce el cliente, aunque el diario esté vacío.
local function scanDungeonMaps()
  dungeonMaps = {}
  local dungeonType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
  for uiMapID = 1, 3000 do
    local info = C.Call("C_Map.GetMapInfo", uiMapID)
    if info and info.mapType == dungeonType and info.name and info.name ~= "" then
      local key = normalize(info.name)
      if not dungeonMaps[key] then dungeonMaps[key] = uiMapID end
    end
  end
end

function J.DungeonMapCount()
  if not dungeonMaps then scanDungeonMaps() end
  local n = 0
  for _ in pairs(dungeonMaps) do n = n + 1 end
  return n
end

-- Mapa de la instancia: diario del cliente, el observado al jugar o, si no,
-- el mapa de mazmorra del cliente con el mismo nombre (en cualquier idioma).
function J.MapFor(d)
  local info = d.instanceID and J.ForInstance(d.instanceID)
  if info and info.uiMapID then return info.uiMapID, "journal" end
  local observed = d.observed and d.observed.uiMapIDs
  if observed and observed[1] then return observed[1], "observed" end
  if not dungeonMaps then scanDungeonMaps() end
  for _, name in pairs(d.name or {}) do
    local uiMapID = dungeonMaps[normalize(name)]
    if uiMapID then return uiMapID, "name" end
  end
  for _, wing in ipairs(d.wings or {}) do
    for _, name in pairs(wing.name or {}) do
      local uiMapID = dungeonMaps[normalize(name)]
      if uiMapID then return uiMapID, "name" end
    end
  end
end

-- Número de instancias del diario (0 si el cliente lo tiene vacío).
function J.InstanceCount()
  if not instances then scanInstances() end
  local n = 0
  for _ in pairs(instances) do n = n + 1 end
  return n
end

-- Plantas del mapa (mazmorras con varios niveles), ordenadas.
function J.Floors(uiMapID)
  local groupID = C.Call("C_Map.GetMapGroupID", uiMapID)
  local members = groupID and C.Call("C_Map.GetMapGroupMembersInfo", groupID)
  if type(members) == "table" and #members > 0 then
    local floors = {}
    for _, m in ipairs(members) do floors[#floors + 1] = { mapID = m.mapID, name = m.name, order = m.relativeHeightIndex or 0 } end
    table.sort(floors, function(a, b) return a.order < b.order end)
    return floors
  end
  local info = C.Call("C_Map.GetMapInfo", uiMapID)
  return { { mapID = uiMapID, name = info and info.name or "" } }
end

-- Texturas del mapa en mosaico, tal como las dibuja el mapa del mundo.
function J.MapArt(uiMapID)
  local layers = C.Call("C_Map.GetMapArtLayers", uiMapID)
  local layer = type(layers) == "table" and layers[1]
  if not layer then return nil end
  local textures = C.Call("C_Map.GetMapArtLayerTextures", uiMapID, 1)
  if type(textures) ~= "table" or #textures == 0 then return nil end
  return {
    width = layer.layerWidth, height = layer.layerHeight,
    tileWidth = layer.tileWidth, tileHeight = layer.tileHeight,
    columns = math.ceil(layer.layerWidth / layer.tileWidth),
    textures = textures,
  }
end

-- Jefes situados en un mapa: { name, x, y } en coordenadas 0..1.
function J.BossPins(uiMapID)
  local out = {}
  local list = C.Call("C_EncounterJournal.GetEncountersOnMap", uiMapID)
  for _, e in ipairs(type(list) == "table" and list or {}) do
    local name = C.Call("EJ_GetEncounterInfo", e.encounterID)
    out[#out + 1] = { name = name or ("#" .. tostring(e.encounterID)), x = e.mapX, y = e.mapY }
  end
  return out
end

local function scanEntrances()
  entrances = {}
  if not C.Has("C_EncounterJournal.GetDungeonEntrancesForMap") then return end
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  -- Recorrido único y perezoso de los mapas de zona; evita incluir IDs de mapa
  -- en los datos, que podrían no coincidir con los de Forever.
  for uiMapID = 1, 3000 do
    local info = C.Call("C_Map.GetMapInfo", uiMapID)
    if info and info.mapType == zoneType then
      for _, e in ipairs(C.Call("C_EncounterJournal.GetDungeonEntrancesForMap", uiMapID) or {}) do
        if e.journalInstanceID and not entrances[e.journalInstanceID] then
          local x, y
          if e.position then x, y = e.position:GetXY() end
          entrances[e.journalInstanceID] = { uiMapID = uiMapID, x = x, y = y, name = e.name, zone = info.name }
        end
      end
    end
  end
end

-- Entrada en el mapa del mundo: la del cliente o la anotada al entrar jugando.
function J.Entrance(d)
  local info = d.instanceID and J.ForInstance(d.instanceID)
  if info then
    if not entrances then scanEntrances() end
    if entrances[info.journalID] then return entrances[info.journalID], "journal" end
  end
  local observed = d.observed and d.observed.entrance
  if observed and observed.mapID then
    return { uiMapID = observed.mapID, x = observed.x, y = observed.y }, "observed"
  end
end

function J.SetWaypoint(uiMapID, x, y)
  if not (uiMapID and x and y) then return false end
  if C.Has("C_Map.SetUserWaypoint") and UiMapPoint and C.Call("C_Map.CanSetUserWaypointOnMap", uiMapID) then
    C.Call("C_Map.SetUserWaypoint", UiMapPoint.CreateFromCoordinates(uiMapID, x, y))
    C.Call("C_SuperTrack.SetSuperTrackedUserWaypoint", true)
    return true
  end
  return false
end

-- Botín de la instancia filtrado por clase y, si se indica, especialización.
function J.Loot(journalID, classID, specID)
  if not journalID or not C.Has("EJ_SelectInstance") then return nil end
  C.Call("EJ_SelectInstance", journalID)
  C.Call("EJ_ResetLootFilter")
  if classID then C.Call("EJ_SetLootFilter", classID, specID or 0) end
  local out = {}
  local count = C.Call("EJ_GetNumLoot") or 0
  for i = 1, count do
    local item = C.Call("C_EncounterJournal.GetLootInfoByIndex", i)
    if type(item) ~= "table" then
      local itemID, encounterID, name, _, slot, armorType, link = C.Call("EJ_GetLootInfoByIndex", i)
      item = itemID and { itemID = itemID, encounterID = encounterID, name = name, slot = slot, armorType = armorType, link = link }
    end
    if item and item.itemID then out[#out + 1] = item end
  end
  C.Call("EJ_ResetLootFilter")
  return out
end

-- Los datos de objetos del diario llegan de forma asíncrona.
ns.On("EJ_LOOT_DATA_RECIEVED", function() ns.Fire("JOURNAL_LOOT_UPDATED") end)

function J.Reset()
  instances, entrances, dungeonMaps = nil, nil, nil
end
