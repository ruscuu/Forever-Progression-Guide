-- Pestaña Buscador: mazmorras, alas y jefes en los dos idiomas.
local _, ns = ...

local UI, D = ns.UI, ns.Dungeons
local L = ns.L

local function matches(text, query)
  return text and string.find(string.lower(text), query, 1, true) ~= nil
end

local function anyName(names, query)
  if type(names) ~= "table" then return matches(names, query) end
  for _, n in pairs(names) do
    if matches(n, query) then return true end
  end
  return false
end

function ns.Search(query)
  query = string.lower(query or "")
  local results = {}
  if #query < 2 then return results end
  for _, d in ipairs(D.All()) do
    if anyName(d.name, query) or anyName(d.zone, query) then
      results[#results + 1] = { kind = "dungeon", label = D.Name(d), dungeon = d }
    end
    for _, w in ipairs(d.wings or {}) do
      if anyName(w.name, query) then
        results[#results + 1] = { kind = "wing", label = D.WingName(w) .. " · " .. D.Name(d), dungeon = d }
      end
    end
    for _, b in ipairs(d.bosses or {}) do
      if anyName(b.name, query) then
        results[#results + 1] = { kind = "boss", label = ns.Localized(b.name) .. " · " .. D.Name(d), dungeon = d }
      end
    end
  end
  return results
end

UI.RegisterTab({
  key = "search",
  Build = function(panel)
    panel.box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.box:SetSize(260, 22)
    panel.box:SetPoint("TOPLEFT", 6, -4)
    panel.box:SetAutoFocus(false)
    panel.hint = UI.Label(panel, "GameFontHighlightSmall")
    panel.hint:SetPoint("LEFT", panel.box, "RIGHT", 10, 0)
    panel.list = UI.List(panel, 20)
    panel.list:SetPoints(0, -34, 0, 0)
    panel.list.onClick = function(r) UI.Select("dungeons", { instanceID = r.dungeon.instanceID }) end
    local function update()
      local results = ns.Search(panel.box:GetText())
      panel.list:SetData(results, function(row, r)
        row.left:SetText(UI.Color("9d9d9d", "[" .. L["KIND_" .. string.upper(r.kind)] .. "] ") .. r.label)
        row.right:SetText("")
      end)
    end
    panel.box:SetScript("OnTextChanged", update)
    panel.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.update = update
  end,
  Refresh = function(panel)
    panel.hint:SetText(L.SEARCH_HINT)
    panel.update()
  end,
})
