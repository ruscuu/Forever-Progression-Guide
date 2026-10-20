-- /wfg traducir: pide al cliente los nombres de todos los objetos y misiones
-- de los datos y los guarda en SavedVariables, en el idioma del cliente.
-- pipeline/import_contributions.py los incorpora a los datos del addon, de
-- modo que quien juegue con el cliente en otro idioma también los vea.
local _, ns = ...

local C = ns.Compat
local T = {}
ns.Translations = T

local BATCH = 40          -- peticiones por tanda
local BATCH_DELAY = 0.5   -- segundos entre tandas
local SETTLE_DELAY = 5    -- espera a que lleguen las últimas respuestas
local MAX_ROUNDS = 3      -- rondas para reintentar lo que no llegó

local running

local function store()
  local locale = GetLocale()
  ns.db.translations = ns.db.translations or {}
  ns.db.translations[locale] = ns.db.translations[locale] or { items = {}, quests = {} }
  return ns.db.translations[locale]
end

local function after(seconds, fn)
  if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

-- Lo que todavía no tiene nombre guardado.
local function pending(saved)
  local list = {}
  for id in pairs(ns.Data.Items or {}) do
    if not saved.items[id] then list[#list + 1] = { kind = "item", id = id } end
  end
  for id in pairs(ns.Data.Quests or {}) do
    if not saved.quests[id] then list[#list + 1] = { kind = "quest", id = id } end
  end
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.id < b.id
  end)
  return list
end

local function request(entry)
  if entry.kind == "item" then
    C.Call("C_Item.RequestLoadItemDataByID", entry.id)
  else
    C.Call("C_QuestLog.RequestLoadQuestByID", entry.id)
  end
end

-- Guarda los nombres que el cliente ya tiene; devuelve cuántos.
local function collect(saved, list)
  local found = 0
  for _, entry in ipairs(list) do
    local name
    if entry.kind == "item" then
      name = C.Call("C_Item.GetItemNameByID", entry.id)
      if name then saved.items[entry.id] = name end
    else
      name = C.Call("C_QuestLog.GetTitleForQuestID", entry.id)
      if name then saved.quests[entry.id] = name end
    end
    if name then found = found + 1 end
  end
  return found
end

function T.Counts()
  local saved = ns.db and ns.db.translations and ns.db.translations[GetLocale()]
  local items, quests = 0, 0
  for _ in pairs(saved and saved.items or {}) do items = items + 1 end
  for _ in pairs(saved and saved.quests or {}) do quests = quests + 1 end
  return items, quests
end

function T.IsRunning() return running end

function T.Start(report)
  if running then return false end
  if not (C.Has("C_Item.RequestLoadItemDataByID") and C.Has("C_Item.GetItemNameByID")) then
    report("unsupported")
    return false
  end
  running = true
  local saved = store()

  local function round(n)
    local list = pending(saved)
    if #list == 0 or n > MAX_ROUNDS then
      running = false
      report("done", T.Counts())
      return
    end
    report("round", n, #list)
    local index = 1
    local function batch()
      for _ = 1, BATCH do
        if index > #list then break end
        request(list[index])
        index = index + 1
      end
      if index <= #list then
        after(BATCH_DELAY, batch)
      else
        after(SETTLE_DELAY, function()
          collect(saved, list)
          round(n + 1)
        end)
      end
    end
    batch()
  end

  round(1)
  return true
end
