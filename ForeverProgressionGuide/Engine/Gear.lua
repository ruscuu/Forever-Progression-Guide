-- Estado del equipo leído del cliente. Solo compara niveles de objeto: es una
-- señal orientativa, no el «mejor equipo» del plan §6.2, que necesita pesos de
-- estadísticas por especialización todavía sin fuente fiable.
local _, ns = ...

local C = ns.Compat
local G = {}
ns.Gear = G

G.SLOTS = {
  { id = 1, key = "HEAD" }, { id = 2, key = "NECK" }, { id = 3, key = "SHOULDER" }, { id = 15, key = "BACK" },
  { id = 5, key = "CHEST" }, { id = 9, key = "WRIST" }, { id = 10, key = "HANDS" }, { id = 6, key = "WAIST" },
  { id = 7, key = "LEGS" }, { id = 8, key = "FEET" }, { id = 11, key = "FINGER1" }, { id = 12, key = "FINGER2" },
  { id = 13, key = "TRINKET1" }, { id = 14, key = "TRINKET2" }, { id = 16, key = "MAINHAND" }, { id = 17, key = "OFFHAND" },
  { id = 18, key = "RANGED" },
}

-- Diferencia con la media a partir de la cual una ranura se considera débil.
G.WEAK_MARGIN = 5

local function isTwoHand(link)
  local fn = C.Has("C_Item.GetItemInfoInstant") and "C_Item.GetItemInfoInstant" or "GetItemInfoInstant"
  local equipLoc = select(4, C.Call(fn, link))
  return equipLoc == "INVTYPE_2HWEAPON"
end

function G.Equipped()
  local out = {}
  local mainHand = GetInventoryItemLink("player", 16)
  for _, slot in ipairs(G.SLOTS) do
    local link = GetInventoryItemLink("player", slot.id)
    local entry = { slot = slot.id, key = slot.key, link = link, itemLevel = C.ItemLevel(link),
                    quality = link and GetInventoryItemQuality("player", slot.id) or nil }
    -- Ranuras vacías que no indican un problema: mano izquierda con arma a dos
    -- manos, o la ranura de rango (no todas las clases ni todos los motores la usan).
    entry.notApplicable = not link and ((slot.key == "OFFHAND" and mainHand and isTwoHand(mainHand)) or slot.key == "RANGED")
    out[#out + 1] = entry
  end
  return out
end

function G.AverageItemLevel(equipped)
  local total, count = 0, 0
  for _, e in ipairs(equipped) do
    if e.itemLevel then total, count = total + e.itemLevel, count + 1 end
  end
  return count > 0 and total / count or nil
end

-- Ranuras vacías o claramente por debajo de la media, de peor a mejor.
function G.WeakSlots(limit)
  local equipped = G.Equipped()
  local average = G.AverageItemLevel(equipped)
  local weak = {}
  for _, e in ipairs(equipped) do
    if not e.notApplicable and (not e.link or (average and e.itemLevel and e.itemLevel < average - G.WEAK_MARGIN)) then
      weak[#weak + 1] = e
    end
  end
  table.sort(weak, function(a, b) return (a.itemLevel or 0) < (b.itemLevel or 0) end)
  while limit and #weak > limit do table.remove(weak) end
  return weak, average
end
