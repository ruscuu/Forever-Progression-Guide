-- Núcleo: espacio de nombres, eventos, variables guardadas y registro de errores.
local ADDON, ns = ...

ns.name = ADDON
ns.errors = {}

local SCHEMA = 1

local DEFAULT_DB = {
  schema = SCHEMA,
  settings = { language = "auto", collect = true, minimap = { angle = 225, hide = false } },
  contributions = { builds = {}, instances = {}, quests = {} },
}

local DEFAULT_CHAR = {
  schema = SCHEMA,
  objectives = {},
  window = {},
}

local function fillDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(target[k]) ~= "table" then target[k] = {} end
      fillDefaults(target[k], v)
    elseif target[k] == nil then
      target[k] = v
    end
  end
  return target
end

-- Migraciones de esquema: cada entrada transforma la versión n-1 en n.
local MIGRATIONS = {}

local function migrate(db)
  for version = (db.schema or 0) + 1, SCHEMA do
    if MIGRATIONS[version] then MIGRATIONS[version](db) end
    db.schema = version
  end
end

function ns.LogError(context, err)
  local entry = tostring(context) .. ": " .. tostring(err)
  if #ns.errors < 50 then table.insert(ns.errors, entry) end
end

-- Ejecuta fn aislando errores para que un módulo roto no tumbe el addon entero.
function ns.Safe(context, fn, ...)
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then
    ns.LogError(context, a)
    return nil
  end
  return a, b, c, d
end

local handlers = {}
local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    ns.Safe(event, list[i], ...)
  end
end)

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- Un evento que no existe en este cliente no debe impedir la carga.
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
      ns.LogError("RegisterEvent", event)
    end
  end
  table.insert(handlers[event], fn)
end

-- Avisos internos entre módulos (no son eventos del cliente).
local listeners = {}

function ns.Listen(message, fn)
  listeners[message] = listeners[message] or {}
  table.insert(listeners[message], fn)
end

function ns.Fire(message, ...)
  for _, fn in ipairs(listeners[message] or {}) do
    ns.Safe(message, fn, ...)
  end
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ForeverProgressionGuideDB = ForeverProgressionGuideDB or {}
  ForeverProgressionGuideCharDB = ForeverProgressionGuideCharDB or {}
  migrate(ForeverProgressionGuideDB)
  migrate(ForeverProgressionGuideCharDB)
  ns.db = fillDefaults(ForeverProgressionGuideDB, DEFAULT_DB)
  ns.char = fillDefaults(ForeverProgressionGuideCharDB, DEFAULT_CHAR)
  ns.SetLanguage(ns.db.settings.language)
  ns.Fire("DB_READY")
end)
