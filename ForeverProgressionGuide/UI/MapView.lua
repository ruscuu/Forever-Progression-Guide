-- Mapa de mazmorra: dibuja los mosaicos del propio cliente, con selector de
-- plantas y los jefes situados según el diario. No se incluye ninguna imagen
-- en el addon, así que el mapa coincide siempre con la versión del juego.
local _, ns = ...

local UI, J = ns.UI, ns.Journal
local L = ns.L

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

function UI.MapView(parent)
  local view = CreateFrame("Frame", nil, parent)
  view.tiles, view.pins, view.floorButtons = {}, {}, {}

  view.canvas = CreateFrame("Frame", nil, view)
  view.canvas:SetPoint("TOPLEFT", 0, -28)
  view.canvas:SetPoint("BOTTOMRIGHT", 0, 0)
  if view.canvas.SetClipsChildren then view.canvas:SetClipsChildren(true) end
  local bg = view.canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)

  view.message = UI.Label(view.canvas, "GameFontNormal", "CENTER")
  view.message:SetPoint("LEFT", 20, 0)
  view.message:SetPoint("RIGHT", -20, 0)

  view.worldMapButton = UI.Button(view, L.MAP_OPEN_WORLD, 150, function()
    if view.mapID then ns.Compat.Call("OpenWorldMap", view.mapID) end
  end)
  view.worldMapButton:SetPoint("TOPRIGHT", 0, -2)

  local function clear()
    for _, t in ipairs(view.tiles) do t:Hide() end
    for _, p in ipairs(view.pins) do p:Hide() end
    view.message:SetText("")
  end

  local function pin(i)
    local p = view.pins[i]
    if not p then
      p = CreateFrame("Button", nil, view.canvas)
      p:SetSize(22, 22)
      p:SetFrameLevel(view.canvas:GetFrameLevel() + 5)
      p.icon = p:CreateTexture(nil, "OVERLAY")
      p.icon:SetAllPoints()
      p.icon:SetTexture(SKULL)
      p.number = UI.Label(p, "GameFontNormalSmall", "CENTER")
      p.number:SetPoint("TOP", p, "BOTTOM", 0, 2)
      p:SetScript("OnEnter", function(self) UI.Tooltip(self, { self.bossName }) end)
      p:SetScript("OnLeave", function() GameTooltip:Hide() end)
      view.pins[i] = p
    end
    return p
  end

  function view:Render(uiMapID)
    clear()
    self.mapID = uiMapID
    local art = J.MapArt(uiMapID)
    if not art then
      self.message:SetText(L.MAP_NO_ART)
      return
    end
    local w, h = self.canvas:GetWidth(), self.canvas:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then
      -- El marco aún no tiene tamaño: se dibuja en el siguiente fotograma.
      if C_Timer and C_Timer.After then C_Timer.After(0, function() self:Render(uiMapID) end) end
      return
    end
    local scale = math.min(w / art.width, h / art.height)
    local ox, oy = (w - art.width * scale) / 2, (h - art.height * scale) / 2
    for i, fileID in ipairs(art.textures) do
      local tile = self.tiles[i]
      if not tile then
        tile = self.canvas:CreateTexture(nil, "ARTWORK")
        self.tiles[i] = tile
      end
      local col, row = (i - 1) % art.columns, math.floor((i - 1) / art.columns)
      tile:SetTexture(fileID)
      tile:SetSize(art.tileWidth * scale, art.tileHeight * scale)
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", ox + col * art.tileWidth * scale, -(oy + row * art.tileHeight * scale))
      tile:Show()
    end
    for i, boss in ipairs(J.BossPins(uiMapID)) do
      local p = pin(i)
      p.bossName = boss.name
      p.number:SetText(i)
      p:ClearAllPoints()
      p:SetPoint("CENTER", self.canvas, "TOPLEFT", ox + boss.x * art.width * scale, -(oy + boss.y * art.height * scale))
      p:Show()
    end
  end

  function view:ShowDungeon(d)
    for _, b in ipairs(self.floorButtons) do b:Hide() end
    local uiMapID = J.MapFor(d)
    if not uiMapID then
      clear()
      self.mapID = nil
      self.message:SetText(L.MAP_NO_ID)
      return
    end
    local floors = J.Floors(uiMapID)
    if #floors > 1 then
      for i, floor in ipairs(floors) do
        local b = self.floorButtons[i]
        if not b then
          b = UI.Button(self, "", 90)
          b:SetPoint("TOPLEFT", (i - 1) * 94, -2)
          self.floorButtons[i] = b
        end
        b:SetText(floor.name ~= "" and floor.name or string.format(L.MAP_FLOOR, i))
        b:SetScript("OnClick", function() self:Render(floor.mapID) end)
        b:Show()
      end
    end
    self:Render(floors[1].mapID)
  end

  return view
end
