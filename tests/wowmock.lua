-- Simulación mínima de la API de WoW para probar el addon sin el cliente.
-- Solo cubre lo que el addon usa; cualquier otro método de marco es un no-op.
local M = { events = {}, printed = {}, scripts = {} }
WOWMOCK = M

M.player = { level = 20, class = "WARRIOR", classID = 1, faction = "Alliance", name = "Tester" }
M.locale = "esES"
M.inInstance, M.instanceType = false, "none"
M.instance = nil
M.mapID = 52
M.position = { 0.42, 0.71 }
M.gear = {}

local methods = {}
local function new(kind)
  local obj = { __kind = kind, __scripts = {}, __shown = true, __text = "", __w = 400, __h = 300, __enabled = true }
  return setmetatable(obj, { __index = function(_, key)
    return methods[key] or function() return nil end
  end })
end
M.new = new

function methods.SetScript(self, name, fn) self.__scripts[name] = fn end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.HookScript(self, name, fn) self.__scripts[name] = fn end
function methods.RegisterEvent(self, event)
  M.events[event] = M.events[event] or {}
  table.insert(M.events[event], self)
end
function methods.Show(self) self.__shown = true end
function methods.Hide(self) self.__shown = false end
function methods.SetShown(self, v) self.__shown = not not v end
function methods.IsShown(self) return self.__shown end
function methods.SetText(self, t) self.__text = t end
function methods.GetText(self) return self.__text end
function methods.SetSize(self, w, h) self.__w, self.__h = w, h end
function methods.SetWidth(self, w) self.__w = w end
function methods.SetHeight(self, h) self.__h = h end
function methods.GetWidth(self) return self.__w end
function methods.GetHeight(self) return self.__h end
function methods.GetStringHeight() return 14 end
function methods.SetEnabled(self, v) self.__enabled = not not v end
function methods.IsEnabled(self) return self.__enabled end
function methods.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods.GetFrameLevel() return 1 end
function methods.SetTexture(self, t) self.__texture = t end
function methods.CreateFontString() return new("FontString") end
function methods.SetChecked(self, v) self.__checked = not not v end
function methods.GetChecked(self) return self.__checked end
function methods.SetPoint(self, ...) self.__point = { ... } end
function methods.GetCenter() return 100, 100 end
function methods.GetEffectiveScale() return 1 end
function methods.CreateTexture() return new("Texture") end

function CreateFrame(kind, name, parent, template)
  local f = new(kind)
  f.__parent, f.__template = parent, template
  if name then _G[name] = f end
  return f
end

function M.Fire(event, ...)
  for _, frame in ipairs(M.events[event] or {}) do
    local handler = frame.__scripts.OnEvent
    if handler then handler(frame, event, ...) end
  end
end

UIParent = new("Frame")
Minimap = new("Frame")
Minimap.__w, Minimap.__h = 140, 140
M.cursor = { 100, 200 }
function GetCursorPosition() return M.cursor[1], M.cursor[2] end

-- API de opciones del juego (motor moderno).
M.settings = {}
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    local category = { frame = frame, name = name, GetID = function() return 42 end }
    M.settings.category = category
    return category
  end,
  RegisterAddOnCategory = function(category) M.settings.registered = category end,
  OpenToCategory = function(id) M.settings.opened = id end,
}
GameTooltip = new("GameTooltip")
UISpecialFrames = {}
SlashCmdList = {}
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Guerrero" }
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4 } }

function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  table.insert(M.printed, table.concat(parts, " "))
end

function GetLocale() return M.locale end
function GetBuildInfo() return "1.60.1", "12345", "Oct 1 2026", 16001 end
function UnitLevel() return M.player.level end
function UnitClass() return "Guerrero", M.player.class, M.player.classID end
function UnitFactionGroup() return M.player.faction end
function UnitName() return M.player.name end
function IsInInstance() return M.inInstance, M.instanceType end
function GetInstanceInfo()
  local i = M.instance
  if not i then return nil end
  return i.name, i.type, 1, "Normal", i.maxPlayers, 0, false, i.instanceID
end
function time() return 1760900000 end
function GetInventoryItemLink(_, slot) return M.gear[slot] end
function GetInventoryItemQuality() return 2 end
function GetInventoryItemTexture(_, slot) return M.gear[slot] and "Interface\\Icons\\Equipped" or nil end

-- Bolsas, estadísticas y tipo de cada objeto (por enlace o por "item:ID").
M.bags, M.itemStats, M.itemInfo, M.itemReq = {}, {}, {}, {}
C_Container = {
  GetContainerNumSlots = function(bag) return #(M.bags[bag] or {}) end,
  GetContainerItemLink = function(bag, slot) return (M.bags[bag] or {})[slot] end,
}
function GetItemInfo(link) return "x", link, 2, 10, M.itemReq[link] end
ITEM_MOD_STRENGTH_SHORT, ITEM_MOD_STAMINA_SHORT, ITEM_MOD_INTELLECT_SHORT = "Fuerza", "Aguante", "Intelecto"

-- Clases y especializaciones del cliente; el sacerdote no tiene, para probar ese caso.
M.classes = { { "Guerrero", "WARRIOR", 1 }, { "Mago", "MAGE", 8 }, { "Sacerdote", "PRIEST", 5 } }
M.specs = {
  [1] = { { 71, "Armas", "DAMAGER" }, { 72, "Furia", "DAMAGER" }, { 73, "Protección", "TANK" } },
  [8] = { { 62, "Arcano", "DAMAGER" }, { 63, "Fuego", "DAMAGER" }, { 64, "Escarcha", "DAMAGER" } },
}
M.playerSpec = 1
function GetNumClasses() return #M.classes end
function GetClassInfo(i) local c = M.classes[i] if c then return c[1], c[2], c[3] end end
function GetNumSpecializationsForClassID(classID) return #(M.specs[classID] or {}) end
function GetSpecializationInfoForClassID(classID, i)
  local s = (M.specs[classID] or {})[i]
  if s then return s[1], s[2], "", 0, s[3] end
end
function GetSpecialization() return M.playerSpec end
function GetSpecializationInfo(i) local s = (M.specs[M.player.classID] or {})[i] if s then return s[1], s[2] end end

local function vector(x, y) return { GetXY = function() return x, y end } end

C_Timer = { After = function(_, fn) fn() end }
-- Nombres que el cliente «tiene en memoria». Con autoLoad, pedirlos los carga al momento.
M.itemNames, M.questTitles, M.requested = {}, {}, {}
M.autoLoad = false
C_Item = {
  GetDetailedItemLevelInfo = function(link) return tonumber(string.match(link, "ilvl(%d+)")) end,
  GetItemNameByID = function(id) return M.itemNames[id] end,
  GetItemStats = function(link) return M.itemStats[link] end,
  GetItemInfoInstant = function(link)
    local i = M.itemInfo[link]
    if i then return i.id, "", "", i.equipLoc, i.icon, i.classID, i.subclassID end
  end,
  RequestLoadItemDataByID = function(id)
    M.requested[#M.requested + 1] = "item:" .. id
    if M.autoLoad then M.itemNames[id] = "Objeto " .. id end
  end,
}

-- Mapa de las Minas de la Muerte: 4x3 mosaicos de 256 px y un jefe situado.
local DEADMINES_MAP = 291
C_Map = {
  GetBestMapForUnit = function() return M.inInstance and DEADMINES_MAP or M.mapID end,
  GetPlayerMapPosition = function() if M.inInstance then return nil end return vector(M.position[1], M.position[2]) end,
  GetMapInfo = function(id)
    if id == 52 then return { mapID = 52, name = "Páramos de Poniente", mapType = 3 } end
    if id == DEADMINES_MAP then return { mapID = id, name = "Las Minas de la Muerte", mapType = 4 } end
  end,
  GetMapGroupID = function() return nil end,
  GetMapArtLayers = function(id)
    if id == DEADMINES_MAP then return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
    return {}
  end,
  GetMapArtLayerTextures = function(id)
    if id ~= DEADMINES_MAP then return {} end
    local t = {}
    for i = 1, 12 do t[i] = 100000 + i end
    return t
  end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(point) M.waypoint = point end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) M.superTracked = v end }
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end }

M.journal = {
  instances = {
    { journalID = 63, name = "Las Minas de la Muerte", description = "Antigua mina de oro.", uiMapID = DEADMINES_MAP, instanceID = 36, isRaid = false },
  },
  encounters = { [63] = { { "Rhahk'Zor", 89, 1 }, { "Sneed", 90, 2 }, { "Edwin VanCleef", 91, 3 } } },
  loot = { { itemID = 5191, name = "Cruel Barb", link = "|Hitem:5191|h[Cruel Barb]|h", slot = "One-Hand" } },
}

local function journalList(isRaid)
  local out = {}
  for _, i in ipairs(M.journal.instances) do
    if i.isRaid == isRaid then out[#out + 1] = i end
  end
  return out
end

function EJ_GetNumTiers() return 1 end
function EJ_GetCurrentTier() return 1 end
function EJ_SelectTier() end
function EJ_GetInstanceByIndex(index, isRaid)
  local i = journalList(isRaid)[index]
  if not i then return nil end
  return i.journalID, i.name, i.description, nil, nil, nil, nil, i.uiMapID, nil, false, i.instanceID
end
function EJ_GetEncounterInfoByIndex(index, journalID)
  local e = (M.journal.encounters[journalID] or {})[index]
  if not e then return nil end
  return e[1], "", e[2], 0, nil, journalID, e[3], 36
end
function EJ_GetEncounterInfo(encounterID)
  for _, list in pairs(M.journal.encounters) do
    for _, e in ipairs(list) do if e[2] == encounterID then return e[1] end end
  end
end
function EJ_SelectInstance(id) M.selectedInstance = id end
function EJ_ResetLootFilter() M.lootFilter, M.lootSpec = nil, nil end
function EJ_SetLootFilter(classID, specID) M.lootFilter, M.lootSpec = classID, specID end
function EJ_GetNumLoot() return M.selectedInstance == 63 and #M.journal.loot or 0 end

C_EncounterJournal = {
  GetEncountersOnMap = function(id)
    if id == DEADMINES_MAP then return { { encounterID = 89, mapX = 0.3, mapY = 0.5 } } end
    return {}
  end,
  GetDungeonEntrancesForMap = function(id)
    if id == 52 then return { { journalInstanceID = 63, name = "Las Minas de la Muerte", position = vector(0.42, 0.72) } } end
    return {}
  end,
  GetLootInfoByIndex = function(i) return M.journal.loot[i] end,
}

M.completedQuests = {}
C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return M.completedQuests[id] or false end,
  GetTitleForQuestID = function(id) return M.questTitles[id] end,
  RequestLoadQuestByID = function(id)
    M.requested[#M.requested + 1] = "quest:" .. id
    if M.autoLoad then M.questTitles[id] = "Misión " .. id end
  end,
  GetLogIndexForQuestID = function() return 1 end,
  GetInfo = function() return { title = "La Hermandad Defias", level = 18, questID = 155, isHeader = false } end,
  GetNumQuestLogEntries = function() return 1 end,
}

-- Escritura de SavedVariables con el mismo formato que el cliente.
local function serialize(value, indent)
  indent = indent or ""
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local lines = { "{" }
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
    lines[#lines + 1] = indent .. "\t" .. key .. " = " .. serialize(value[k], indent .. "\t") .. ","
  end
  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

function M.SavedVariablesText(name)
  return name .. " = " .. serialize(_G[name]) .. "\n"
end
