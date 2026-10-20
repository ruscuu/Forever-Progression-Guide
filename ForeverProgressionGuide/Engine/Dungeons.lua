-- Recomendación de mazmorras (plan §6.1). Clasifica cada mazmorra para el
-- personaje y explica el motivo; nunca inventa un rango de niveles.
local _, ns = ...

local D = {}
ns.Dungeons = D

D.RECOMMENDED = "recommended"
D.REWARD = "reward"         -- reservado para cuando haya datos fiables de objetos
D.OPTIONAL = "optional"
D.TOO_EARLY = "too_early"
D.UNVERIFIED = "unverified"
D.UNAVAILABLE = "unavailable" -- anunciada o cerrada todavía en Forever

local CATEGORY_RANK = { recommended = 1, reward = 2, unverified = 3, optional = 4, too_early = 5, unavailable = 6 }
local CONFIDENCE = { verified_ingame = "high", datamined = "medium", classic_inherited = "low", announced = "low", unknown = "none" }

-- Niveles por debajo del mínimo en los que una mazmorra ya se puede intentar.
D.EARLY_MARGIN = 2

function D.Confidence(d, field)
  local prov = d.provenance or {}
  local status = prov[field] or d.status or "unknown"
  return CONFIDENCE[status] or "none", status
end

function D.Name(d) return ns.Localized(d.name) or tostring(d.id) end
function D.ZoneName(d) return ns.Localized(d.zone) end
function D.WingName(w) return w and ns.Localized(w.name) end

local function classifyRange(levels, playerLevel)
  if not levels or not levels.min or not levels.max then
    return D.UNVERIFIED, { { "no_levels" } }
  end
  if playerLevel < levels.min - D.EARLY_MARGIN then
    return D.TOO_EARLY, { { "needs_level", levels.min - D.EARLY_MARGIN } }
  end
  if playerLevel > levels.max then
    return D.OPTIONAL, { { "overleveled", levels.max } }
  end
  return D.RECOMMENDED, { { "in_range", levels.min, levels.max } }
end

local function distance(levels, playerLevel)
  if not levels or not levels.min then return math.huge end
  return math.abs(playerLevel - (levels.min + levels.max) / 2)
end

-- Devuelve { category, reasons, wing, levels, confidence, levelStatus, distance }.
function D.Evaluate(d, player)
  local best
  local parts = (d.wings and #d.wings > 0) and d.wings or { false }
  for _, wing in ipairs(parts) do
    local levels = wing and wing.levels or d.levels
    local category, reasons = classifyRange(levels, player.level)
    local candidate = { category = category, reasons = reasons, wing = wing or nil, levels = levels,
                        distance = distance(levels, player.level) }
    if not best or CATEGORY_RANK[category] < CATEGORY_RANK[best.category]
        or (category == best.category and candidate.distance < best.distance) then
      best = candidate
    end
  end

  if d.available == false then
    best.category = D.UNAVAILABLE
    table.insert(best.reasons, 1, { "unavailable" })
  elseif d.faction and d.faction ~= "both" and d.faction ~= player.faction and best.category == D.RECOMMENDED then
    best.category = D.OPTIONAL
    table.insert(best.reasons, { "other_faction" })
  end

  best.confidence, best.levelStatus = D.Confidence(d, "levels")
  if best.levels and best.confidence ~= "high" then
    table.insert(best.reasons, { "levels_" .. best.levelStatus })
  end
  if not (d.provenance and d.provenance.exists) then
    table.insert(best.reasons, { "not_seen_ingame" })
  end
  return best
end

-- Registros mínimos para instancias que el cliente conoce pero los datos no.
local function discoveredRecords()
  local out = {}
  for _, info in ipairs(ns.Journal.Undocumented()) do
    out[#out + 1] = {
      id = "journal-" .. info.instanceID,
      instanceID = info.instanceID,
      type = info.isRaid and "raid" or "dungeon",
      name = { [ns.lang] = info.name },
      status = "datamined",
      provenance = { exists = "datamined" },
      bosses = {},
      discovered = true,
    }
  end
  return out
end

function D.All()
  local list = {}
  for _, d in pairs(ns.Data.Dungeons or {}) do list[#list + 1] = d end
  for _, d in ipairs(discoveredRecords()) do list[#list + 1] = d end
  table.sort(list, function(a, b)
    local la = a.levels and a.levels.min or 999
    local lb = b.levels and b.levels.min or 999
    if la ~= lb then return la < lb end
    return D.Name(a) < D.Name(b)
  end)
  return list
end

-- Por id de la guía ("the-deadmines") o por ID de instancia del juego.
function D.Get(key)
  local d = ns.Data.Dungeons and ns.Data.Dungeons[key]
  if d then return d end
  for _, rec in pairs(ns.Data.Dungeons or {}) do
    if rec.instanceID == key then return rec end
  end
  for _, rec in ipairs(discoveredRecords()) do
    if rec.id == key or rec.instanceID == key then return rec end
  end
end

-- ¿Hay alguna mazmorra con este ID de instancia en los datos?
function D.HasInstance(instanceID)
  for _, rec in pairs(ns.Data.Dungeons or {}) do
    if rec.instanceID == instanceID then return true end
  end
  return false
end

-- Mazmorras evaluadas, con las recomendadas primero y ordenadas por cercanía al nivel.
function D.Ranked(player)
  local ranked = {}
  for _, d in ipairs(D.All()) do
    ranked[#ranked + 1] = { dungeon = d, eval = D.Evaluate(d, player) }
  end
  table.sort(ranked, function(a, b)
    local ra, rb = CATEGORY_RANK[a.eval.category], CATEGORY_RANK[b.eval.category]
    if ra ~= rb then return ra < rb end
    return a.eval.distance < b.eval.distance
  end)
  return ranked
end

-- Jefes: primero los del diario del cliente (siempre actuales y traducidos),
-- después los de los datos incluidos.
function D.Bosses(d)
  local journal = d.instanceID and ns.Journal.ForInstance(d.instanceID)
  if journal then
    local encounters = ns.Journal.Encounters(journal.journalID)
    if #encounters > 0 then return encounters, "journal" end
  end
  local out = {}
  for _, b in ipairs(d.bosses or {}) do
    out[#out + 1] = { name = ns.Localized(b.name), wing = b.wing }
  end
  return out, "data"
end
