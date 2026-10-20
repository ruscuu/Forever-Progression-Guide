-- Acceso seguro a la API del cliente. Forever usa un motor moderno, pero no
-- todas las funciones existen o funcionan igual: cada llamada se comprueba.
local _, ns = ...

local C = {}
ns.Compat = C

local function resolve(path)
  local obj = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(obj) ~= "table" then return nil end
    obj = obj[part]
  end
  return obj
end

function C.Has(path)
  return type(resolve(path)) == "function"
end

-- Llama a la función indicada si existe; devuelve nil si falta o falla.
function C.Call(path, ...)
  local fn = resolve(path)
  if type(fn) ~= "function" then return nil end
  local results = { n = 0 }
  local function pack(...)
    results.n = select("#", ...)
    for i = 1, results.n do results[i] = select(i, ...) end
  end
  pack(pcall(fn, ...))
  if not results[1] then
    ns.LogError(path, results[2])
    return nil
  end
  return unpack(results, 2, results.n)
end

function C.ClientBuild()
  local version, build = GetBuildInfo()
  return (version or "?") .. "." .. (build or "?")
end

-- Compara dos builds tipo "1.60.1.12345"; devuelve -1, 0 o 1.
function C.CompareBuilds(a, b)
  local pa, pb = {}, {}
  for n in string.gmatch(a or "", "%d+") do pa[#pa + 1] = tonumber(n) end
  for n in string.gmatch(b or "", "%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

function C.Player()
  local _, classFile, classID = UnitClass("player")
  local faction = UnitFactionGroup("player")
  return {
    level = UnitLevel("player") or 1,
    class = classFile,
    classID = classID,
    faction = faction and string.lower(faction) or "neutral",
    name = UnitName("player"),
  }
end

function C.ItemLevel(link)
  if not link then return nil end
  return C.Call("C_Item.GetDetailedItemLevelInfo", link) or C.Call("GetDetailedItemLevelInfo", link)
end

function C.AddOnVersion()
  local v = C.Call("C_AddOns.GetAddOnMetadata", ns.name, "Version") or C.Call("GetAddOnMetadata", ns.name, "Version")
  if not v or string.find(v, "@", 1, true) then return "dev" end
  return v
end
