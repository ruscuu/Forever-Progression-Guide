-- /wfg test: autoprueba dentro del juego. Comprueba qué funciones del cliente
-- existen, que los datos están cargados y que cada pestaña, mazmorra y modo se
-- dibuja sin errores. El informe se puede copiar para diagnosticar problemas.
local _, ns = ...

local C = ns.Compat
local S = {}
ns.SelfTest = S

-- Funciones del cliente de las que depende alguna parte de la guía.
S.APIS = {
  "C_Map.GetMapInfo", "C_Map.GetMapArtLayerTextures", "C_Map.GetBestMapForUnit", "C_Map.SetUserWaypoint",
  "EJ_GetInstanceByIndex", "C_EncounterJournal.GetEncountersOnMap",
  "C_Item.GetItemNameByID", "C_Item.RequestLoadItemDataByID", "C_Item.GetDetailedItemLevelInfo",
  "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.GetTitleForQuestID", "C_QuestLog.RequestLoadQuestByID",
  "GetSpecializationInfoForClassID", "GetClassInfo", "Settings.RegisterCanvasLayoutCategory",
}

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- Ejecuta fn y devuelve cuántos errores nuevos registró el addon (incluidos
-- los que los módulos capturan por su cuenta con ns.Safe).
local function errorsDuring(fn)
  local before = ns.errorCount
  local ok, err = pcall(fn)
  if not ok then ns.LogError("SelfTest", err) end
  return ns.errorCount - before
end

function S.Run()
  local report = { missing = {}, failures = {} }

  for _, api in ipairs(S.APIS) do
    if not C.Has(api) then report.missing[#report.missing + 1] = api end
  end
  report.apis = #S.APIS

  report.data = {
    dungeons = count(ns.Data.Dungeons), quests = count(ns.Data.Quests), items = count(ns.Data.Items),
    zones = count(ns.Data.Zones), classQuests = count(ns.Data.ClassQuests),
  }
  report.journal = ns.Journal.InstanceCount()
  report.dungeonMaps = ns.Journal.DungeonMapCount()

  local wasShown = ns.UI.IsShown()
  ns.UI.Show("progress")
  for _, tab in ipairs({ "progress", "dungeons", "gear", "quests", "professions", "search", "options" }) do
    local n = errorsDuring(function() ns.UI.Select(tab) end)
    if n > 0 then report.failures[#report.failures + 1] = "tab:" .. tab end
  end

  local ids = {}
  for id in pairs(ns.Data.Dungeons or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  report.dungeonsChecked = #ids
  for _, id in ipairs(ids) do
    local n = errorsDuring(function()
      ns.UI.Select("dungeons", { id = id })
      local panel = ns.UI.tabs.dungeons.panel
      for _, mode in ipairs({ "quests", "loot", "map", "info" }) do
        local button = panel.modes[mode]
        button:GetScript("OnClick")(button)
      end
    end)
    if n > 0 then report.failures[#report.failures + 1] = "dungeon:" .. id end
  end

  ns.UI.Select("progress")
  if not wasShown then ns.UI.Toggle() end
  report.errors = ns.errorCount
  return report
end
