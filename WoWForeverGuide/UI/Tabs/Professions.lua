-- Pestaña Profesiones: profesiones y habilidad actuales. Las rutas de
-- fabricación (plan §6.4) esperan a tener recetas verificadas (COBERTURA §4).
local _, ns = ...

local UI, C = ns.UI, ns.Compat
local L = ns.L

local function professions()
  local out = {}
  if C.Has("GetProfessions") and C.Has("GetProfessionInfo") then
    -- GetProfessions devuelve huecos (nil) para las profesiones que no se tienen.
    local indices = { C.Call("GetProfessions") }
    for i = 1, 6 do
      local index = indices[i]
      if index then
        local name, _, rank, maxRank = C.Call("GetProfessionInfo", index)
        if name then out[#out + 1] = { name = name, rank = rank, maxRank = maxRank } end
      end
    end
  elseif C.Has("GetSkillLineInfo") then
    for i = 1, C.Call("GetNumSkillLines") or 0 do
      local name, isHeader, _, rank, _, _, maxRank = C.Call("GetSkillLineInfo", i)
      if name then out[#out + 1] = { name = name, isHeader = isHeader, rank = rank, maxRank = maxRank } end
    end
  end
  return out
end

UI.RegisterTab({
  key = "professions",
  Build = function(panel)
    panel.intro = UI.Label(panel, "GameFontHighlightSmall")
    panel.intro:SetPoint("TOPLEFT", 0, 0)
    panel.intro:SetPoint("RIGHT", 0, 0)
    panel.list = UI.List(panel, 20)
    panel.list:SetPoints(0, -60, 0, 0)
  end,
  Refresh = function(panel)
    panel.intro:SetText(L.PROFESSIONS_INTRO)
    local rows = professions()
    panel.list:SetData(rows, function(row, p)
      row.left:SetText(p.isHeader and UI.Color("ffd100", p.name) or ("   " .. p.name))
      row.right:SetText((not p.isHeader and p.rank) and (p.rank .. " / " .. (p.maxRank or "?")) or "")
    end)
  end,
})
