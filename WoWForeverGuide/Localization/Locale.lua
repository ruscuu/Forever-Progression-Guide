-- Motor de idiomas. El idioma del addon es independiente del cliente:
-- "auto" sigue al cliente; "es" y "en" lo fijan.
local _, ns = ...

ns.Locales = {}
ns.lang = "en"
ns.missingStrings = {}

local function lookup(key)
  local t = ns.Locales[ns.lang]
  local value = t and t[key]
  if value == nil then value = ns.Locales.en and ns.Locales.en[key] end
  if value == nil then
    ns.missingStrings[key] = true
    return key
  end
  return value
end

ns.L = setmetatable({}, { __index = function(_, key) return lookup(key) end })

function ns.SetLanguage(setting)
  if setting == "es" or setting == "en" then
    ns.lang = setting
  else
    local locale = GetLocale()
    ns.lang = (locale == "esES" or locale == "esMX") and "es" or "en"
  end
end

-- Elige el nombre en el idioma activo; sin traducción, el original disponible.
function ns.Localized(names)
  if type(names) ~= "table" then return names end
  return names[ns.lang] or names.en or names.es or select(2, next(names))
end

function ns.FormatReason(reason)
  return string.format(ns.L["REASON_" .. string.upper(reason[1])], unpack(reason, 2))
end
