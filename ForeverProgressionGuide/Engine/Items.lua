-- Objetos: nombre, icono y calidad, qué clases pueden usarlos y si mejoran
-- el equipo actual. Los datos vienen de Forever Companion; nombre e icono se
-- piden antes al cliente, que los da en el idioma del juego.
local _, ns = ...

local C = ns.Compat
local I = {}
ns.Items = I

I.QUALITY_COLORS = {
  poor = "9d9d9d", common = "ffffff", uncommon = "1eff00", rare = "0070dd", epic = "a335ee", legendary = "ff8000",
}

-- Ranuras de inventario donde va cada tipo de objeto.
local SLOT_TO_INVENTORY = {
  Head = { 1 }, Neck = { 2 }, Shoulder = { 3 }, Back = { 15 }, Chest = { 5 }, Wrist = { 9 }, Hands = { 10 },
  Waist = { 6 }, Legs = { 7 }, Feet = { 8 }, Finger = { 11, 12 }, Trinket = { 13, 14 },
  ["One-Hand"] = { 16, 17 }, ["Two-Hand"] = { 16 }, ["Main Hand"] = { 16 }, ["Off Hand"] = { 17 },
  ["Held In Off-hand"] = { 17 }, Ranged = { 18 },
}

-- Reglas de Classic: armadura que cada clase puede llevar y la que le conviene
-- (la de mallas y placas se aprende a nivel 40).
local ARMOR = {
  WARRIOR = { usable = { "cloth", "leather", "mail", "plate" }, best = "mail", best40 = "plate" },
  PALADIN = { usable = { "cloth", "leather", "mail", "plate" }, best = "mail", best40 = "plate" },
  HUNTER = { usable = { "cloth", "leather", "mail" }, best = "leather", best40 = "mail" },
  SHAMAN = { usable = { "cloth", "leather", "mail" }, best = "leather", best40 = "mail" },
  ROGUE = { usable = { "cloth", "leather" }, best = "leather" },
  DRUID = { usable = { "cloth", "leather" }, best = "leather" },
  MAGE = { usable = { "cloth" }, best = "cloth" },
  PRIEST = { usable = { "cloth" }, best = "cloth" },
  WARLOCK = { usable = { "cloth" }, best = "cloth" },
}
local LATE_ARMOR_LEVEL = 40

-- Tipos de arma que cada clase puede aprender. Una entrada "1H" limita el
-- arma a una mano (por ejemplo, el pícaro no usa espadas a dos manos).
local WEAPONS = {
  WARRIOR = { Axe = true, Sword = true, Mace = true, Dagger = true, ["Fist Weapon"] = true, Polearm = true, Staff = true,
              Bow = true, Gun = true, Crossbow = true, Thrown = true, Shield = true },
  PALADIN = { Axe = true, Sword = true, Mace = true, Polearm = true, Shield = true },
  HUNTER = { Axe = true, Sword = true, Dagger = true, ["Fist Weapon"] = true, Polearm = true, Staff = true,
             Bow = true, Gun = true, Crossbow = true, Thrown = true },
  ROGUE = { Dagger = true, Sword = "1H", Mace = "1H", ["Fist Weapon"] = true, Bow = true, Gun = true, Crossbow = true, Thrown = true },
  SHAMAN = { Axe = true, Mace = true, Dagger = true, ["Fist Weapon"] = true, Staff = true, Shield = true },
  DRUID = { Dagger = true, ["Fist Weapon"] = true, Mace = true, Staff = true },
  MAGE = { Dagger = true, Sword = "1H", Staff = true, Wand = true },
  PRIEST = { Dagger = true, Mace = "1H", Staff = true, Wand = true },
  WARLOCK = { Dagger = true, Sword = "1H", Staff = true, Wand = true },
}

-- Estadísticas que interesan a cada clase (orientativo, sin pesos finos).
local STATS = {
  WARRIOR = { str = true, sta = true, agi = true, def = true, ap = true, crit = true },
  PALADIN = { str = true, sta = true, int = true, sp = true, healing = true, crit = true },
  HUNTER = { agi = true, sta = true, int = true, ap = true, crit = true },
  ROGUE = { agi = true, sta = true, str = true, ap = true, crit = true },
  SHAMAN = { int = true, sta = true, str = true, agi = true, sp = true, healing = true, nature = true },
  DRUID = { int = true, spi = true, sta = true, agi = true, str = true, sp = true, healing = true, nature = true },
  MAGE = { int = true, sta = true, spi = true, sp = true, fire = true, frost = true },
  PRIEST = { int = true, spi = true, sta = true, sp = true, healing = true, shadow = true },
  WARLOCK = { int = true, sta = true, spi = true, sp = true, shadow = true, fire = true },
}

function I.Get(id) return ns.Data.Items and ns.Data.Items[id] end

function I.Name(id)
  local name = C.Call("C_Item.GetItemNameByID", id)
  if name then return name end
  local item = I.Get(id)
  return item and item.name or ("#" .. tostring(id))
end

function I.Icon(id)
  local item = I.Get(id)
  if item and item.icon then return "Interface\\Icons\\" .. item.icon end
  return C.Call("C_Item.GetItemIconByID", id) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function I.Color(id)
  local item = I.Get(id)
  return I.QUALITY_COLORS[item and item.quality or "common"] or "ffffff"
end

function I.ColoredName(id)
  return "|cff" .. I.Color(id) .. I.Name(id) .. "|r"
end

local function contains(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end

-- "best": le conviene a la clase; "usable": la puede usar pero no es ideal;
-- "no": no la puede usar. Sin datos de armadura o arma se considera utilizable.
function I.Fit(item, classFile, level)
  if not item or not classFile then return "usable" end
  local armorRule, weapons, stats = ARMOR[classFile], WEAPONS[classFile], STATS[classFile]
  if not armorRule then return "usable" end

  if item.armor then
    if not contains(armorRule.usable, item.armor) then return "no" end
    local best = (level or 1) >= LATE_ARMOR_LEVEL and armorRule.best40 or armorRule.best
    if item.armor ~= best then return "usable" end
  elseif item.weapon and item.weapon ~= "Miscellaneous" then
    local rule = weapons[item.weapon]
    if not rule then return "no" end
    if rule == "1H" and item.slot == "Two-Hand" then return "no" end
  end

  if item.stats and #item.stats > 0 then
    for _, stat in ipairs(item.stats) do
      if stats[stat] then return "best" end
    end
    return "usable"
  end
  return "best"
end

-- Diferencia de nivel de objeto con lo que llevas en esa ranura (la peor de
-- las dos en anillos, abalorios y armas a una mano). nil si no se puede comparar.
function I.Upgrade(item)
  if not item or not item.ilvl or not item.slot then return nil end
  local slots = SLOT_TO_INVENTORY[item.slot]
  if not slots then return nil end
  local worst
  for _, slot in ipairs(slots) do
    local link = GetInventoryItemLink("player", slot)
    local equipped = link and C.ItemLevel(link) or 0
    if not worst or equipped < worst then worst = equipped end
  end
  return item.ilvl - (worst or 0)
end

function I.ShowTooltip(owner, id)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(id)
  else
    GameTooltip:SetHyperlink("item:" .. id)
  end
  GameTooltip:Show()
end

-- Botín de una mazmorra preparado para mostrar, filtrado para una clase.
function I.DungeonLoot(d, classFile, level, onlyUsable)
  local out = {}
  for _, drop in ipairs(d.loot or {}) do
    local item = I.Get(drop.itemId)
    local fit = I.Fit(item, classFile, level)
    if not onlyUsable or fit ~= "no" then
      out[#out + 1] = { id = drop.itemId, source = drop.source, item = item, fit = fit, upgrade = I.Upgrade(item) }
    end
  end
  local fitRank = { best = 1, usable = 2, no = 3 }
  table.sort(out, function(a, b)
    if fitRank[a.fit] ~= fitRank[b.fit] then return fitRank[a.fit] < fitRank[b.fit] end
    return (a.upgrade or -999) > (b.upgrade or -999)
  end)
  return out
end
