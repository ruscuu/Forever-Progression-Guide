-- Clase y especialización con las que se filtra la guía. Por defecto, las del
-- personaje; se pueden cambiar para consultar otra clase. Las listas salen del
-- cliente, así que solo aparecen las clases y especializaciones de Forever.
local _, ns = ...

local C = ns.Compat
local F = {}
ns.ClassFilter = F

F.ALL_SPECS = 0

function F.Classes()
  local out = {}
  for i = 1, C.Call("GetNumClasses") or 0 do
    local name, classFile, classID = C.Call("GetClassInfo", i)
    if classID then out[#out + 1] = { classID = classID, classFile = classFile, name = name } end
  end
  return out
end

-- Lista vacía si el cliente no tiene especializaciones para esa clase.
function F.Specs(classID)
  local out = {}
  for i = 1, C.Call("GetNumSpecializationsForClassID", classID) or 0 do
    local specID, name, _, icon, role = C.Call("GetSpecializationInfoForClassID", classID, i)
    if specID then out[#out + 1] = { specID = specID, name = name, icon = icon, role = role } end
  end
  return out
end

local function playerSpecID()
  local index = C.Call("GetSpecialization")
  local specID = index and C.Call("GetSpecializationInfo", index)
  return specID or F.ALL_SPECS
end

-- Selección efectiva: { classID, specID, className, specName, role, isPlayer }.
function F.Current()
  local player = C.Player()
  local saved = ns.char and ns.char.filter or {}
  local classID = saved.classID or player.classID
  local specID = saved.classID and (saved.specID or F.ALL_SPECS) or playerSpecID()

  local current = { classID = classID, specID = specID, isPlayer = not saved.classID }
  for _, c in ipairs(F.Classes()) do
    if c.classID == classID then current.className, current.classFile = c.name, c.classFile end
  end
  current.className = current.className or (classID == player.classID and player.class) or tostring(classID)
  for _, s in ipairs(F.Specs(classID)) do
    if s.specID == specID then current.specName, current.role = s.name, s.role end
  end
  return current
end

-- Cambiar de clase vuelve a «todas las especializaciones» de la nueva clase.
function F.SetClass(classID)
  local player = C.Player()
  if classID == player.classID then
    ns.char.filter = {}
  else
    ns.char.filter = { classID = classID, specID = F.ALL_SPECS }
  end
  ns.Fire("FILTER_CHANGED")
end

function F.SetSpec(specID)
  local current = F.Current()
  ns.char.filter = { classID = current.classID, specID = specID }
  ns.Fire("FILTER_CHANGED")
end

function F.Reset()
  ns.char.filter = {}
  ns.Fire("FILTER_CHANGED")
end

function F.Label(current)
  current = current or F.Current()
  if current.specName then return current.className .. " · " .. current.specName end
  return current.className
end
