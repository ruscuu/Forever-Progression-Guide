-- Comparación de objetos por estadísticas: puntúa cada objeto con pesos según
-- la clase y el rol, y lo compara con lo que llevas en esa ranura. Las
-- estadísticas salen del cliente (GetItemStats), así que son las de Forever.
-- Los pesos son orientativos: sirven para ordenar, no para optimizar al detalle.
local _, ns = ...

local C = ns.Compat
local W = {}
ns.Compare = W

-- Claves de estadística del cliente (los nombres traducidos están en _G[clave]).
local STR, AGI, STA, INT, SPI = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local AP, SP, HEAL = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local CRIT, HIT, DEF = "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"
local ARMOR, DPS = "RESISTANCE0_NAME", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

local WEIGHTS = {
  melee_str = { [STR] = 1, [AGI] = 0.6, [STA] = 0.5, [AP] = 0.5, [CRIT] = 0.8, [HIT] = 0.8, [ARMOR] = 0.01, [DPS] = 3 },
  melee_agi = { [AGI] = 1, [STR] = 0.4, [STA] = 0.5, [AP] = 0.5, [CRIT] = 0.8, [HIT] = 0.8, [ARMOR] = 0.01, [DPS] = 3 },
  hunter = { [AGI] = 1, [INT] = 0.3, [STA] = 0.5, [AP] = 0.5, [CRIT] = 0.8, [HIT] = 0.8, [ARMOR] = 0.01, [DPS] = 2 },
  tank = { [STA] = 1, [DEF] = 1, [STR] = 0.6, [AGI] = 0.6, [ARMOR] = 0.05, [HIT] = 0.4, [DPS] = 1 },
  caster = { [INT] = 0.8, [SP] = 1, [CRIT] = 0.8, [HIT] = 0.8, [STA] = 0.4, [SPI] = 0.3, [ARMOR] = 0.005 },
  healer = { [INT] = 1, [HEAL] = 1, [SP] = 0.8, [SPI] = 0.6, [STA] = 0.3, [ARMOR] = 0.005 },
  hybrid = { [INT] = 0.6, [STR] = 0.6, [AGI] = 0.5, [STA] = 0.5, [SP] = 0.6, [SPI] = 0.3, [AP] = 0.4, [ARMOR] = 0.01, [DPS] = 2 },
}

local CLASS_PROFILE = {
  WARRIOR = "melee_str", PALADIN = "melee_str", ROGUE = "melee_agi", HUNTER = "hunter",
  MAGE = "caster", WARLOCK = "caster", PRIEST = "healer", SHAMAN = "hybrid", DRUID = "hybrid",
}

-- Perfil de pesos: el rol de la especialización manda si se conoce.
function W.Profile(classFile, role)
  if role == "TANK" then return "tank" end
  if role == "HEALER" then return "healer" end
  if role == "DAMAGER" and (classFile == "PRIEST" or classFile == "SHAMAN" or classFile == "DRUID") then
    return classFile == "DRUID" and "hybrid" or "caster"
  end
  return CLASS_PROFILE[classFile] or "hybrid"
end

function W.Weights(classFile, role)
  return WEIGHTS[W.Profile(classFile, role)]
end

-- Estadísticas de un objeto (enlace o "item:ID"); nil si el cliente aún no lo tiene.
function W.Stats(link)
  if not link then return nil end
  local stats = C.Call("C_Item.GetItemStats", link) or C.Call("GetItemStats", link)
  return type(stats) == "table" and stats or nil
end

function W.Score(stats, weights)
  local score = 0
  for key, value in pairs(stats or {}) do
    score = score + (weights[key] or 0) * value
  end
  return score
end

-- Diferencias de estadística de b respecto a a, ordenadas por importancia.
function W.Diff(a, b, weights)
  local keys, out = {}, {}
  for k in pairs(a or {}) do keys[k] = true end
  for k in pairs(b or {}) do keys[k] = true end
  for k in pairs(keys) do
    local delta = ((b or {})[k] or 0) - ((a or {})[k] or 0)
    if delta ~= 0 then out[#out + 1] = { key = k, delta = delta, weight = weights[k] or 0 } end
  end
  table.sort(out, function(x, y)
    if x.weight ~= y.weight then return x.weight > y.weight end
    return x.key < y.key
  end)
  return out
end

function W.DiffText(diffs, limit)
  local parts = {}
  for i, d in ipairs(diffs) do
    if i > (limit or 4) then break end
    local label = _G[d.key] or d.key
    local rounded = d.delta > 0 and math.floor(d.delta + 0.5) or -math.floor(-d.delta + 0.5)
    local color = d.delta > 0 and "40ff40" or "ff5050"
    parts[#parts + 1] = "|cff" .. color .. (d.delta > 0 and "+" or "") .. rounded .. " " .. label .. "|r"
  end
  return table.concat(parts, ", ")
end

-- Ranuras de inventario según el tipo de equipo del cliente.
local EQUIP_SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
}
W.EQUIP_SLOTS = EQUIP_SLOTS

-- Subclases del cliente traducidas a los nombres que usa ns.Items.Fit.
local ARMOR_SUBCLASS = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate" }
local WEAPON_SUBCLASS = {
  [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm", [7] = "Sword",
  [8] = "Sword", [10] = "Staff", [13] = "Fist Weapon", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand",
}

local function itemInfo(link)
  local fn = C.Has("C_Item.GetItemInfoInstant") and "C_Item.GetItemInfoInstant" or "GetItemInfoInstant"
  local itemID, _, _, equipLoc, icon, classID, subclassID = C.Call(fn, link)
  return itemID, equipLoc, icon, classID, subclassID
end

-- Datos para Items.Fit a partir del cliente.
local function fitInfo(link, equipLoc, classID, subclassID)
  local info = { slot = equipLoc == "INVTYPE_2HWEAPON" and "Two-Hand" or nil }
  if classID == 4 then info.armor = ARMOR_SUBCLASS[subclassID]
  elseif classID == 2 then info.weapon = WEAPON_SUBCLASS[subclassID] or "Miscellaneous" end
  if subclassID == 6 and classID == 4 then info.weapon = "Shield" end
  return info
end

local function requiredLevel(link)
  local fn = C.Has("C_Item.GetItemInfo") and "C_Item.GetItemInfo" or "GetItemInfo"
  return (select(5, C.Call(fn, link)))
end

-- Compara un objeto con lo que llevas en sus ranuras (contra el peor de dos).
-- Devuelve { slot, equippedLink, delta, diffs } o nil si no es equipo.
function W.Against(link, weights)
  local _, equipLoc = itemInfo(link)
  local slots = EQUIP_SLOTS[equipLoc or ""]
  local stats = W.Stats(link)
  if not slots or not stats then return nil end
  local best
  for _, slot in ipairs(slots) do
    local equippedLink = GetInventoryItemLink("player", slot)
    local equippedStats = W.Stats(equippedLink) or {}
    local delta = W.Score(stats, weights) - W.Score(equippedStats, weights)
    if not best or delta > best.delta then
      best = { slot = slot, equippedLink = equippedLink, delta = delta, diffs = W.Diff(equippedStats, stats, weights) }
    end
  end
  return best
end

local function containerCall(name, ...)
  return C.Call("C_Container." .. name, ...) or C.Call(name, ...)
end

-- Objetos de las bolsas que mejoran el equipo para la clase y rol indicados.
function W.BagUpgrades(classFile, role, level)
  local weights = W.Weights(classFile, role)
  local out = {}
  for bag = 0, 4 do
    for slot = 1, containerCall("GetContainerNumSlots", bag) or 0 do
      local link = containerCall("GetContainerItemLink", bag, slot)
      if link then
        local itemID, equipLoc, icon, classID, subclassID = itemInfo(link)
        if EQUIP_SLOTS[equipLoc or ""] then
          local fit = ns.Items.Fit(fitInfo(link, equipLoc, classID, subclassID), classFile, level)
          local cmp = fit ~= "no" and W.Against(link, weights)
          if cmp and cmp.delta > 0 then
            local req = requiredLevel(link)
            out[#out + 1] = { link = link, itemID = itemID, icon = icon, bag = bag, bagSlot = slot, fit = fit,
                              slot = cmp.slot, delta = cmp.delta, diffs = cmp.diffs, equippedLink = cmp.equippedLink,
                              future = req and req > level and req or nil }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if (a.future ~= nil) ~= (b.future ~= nil) then return a.future == nil end
    return a.delta > b.delta
  end)
  return out
end

-- Comparación de un objeto por ID (botín de mazmorras). nil si el cliente no
-- tiene todavía sus estadísticas; ns.Items lo pide y la ventana se redibuja.
function W.ForItemID(id, classFile, role)
  local link = "item:" .. id
  if not W.Stats(link) then
    ns.Items.Request(id)
    return nil
  end
  return W.Against(link, W.Weights(classFile, role))
end
