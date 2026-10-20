-- Botón en el borde del minimapa: clic izquierdo abre la guía, clic derecho
-- abre las opciones y arrastrándolo se mueve alrededor del minimapa.
local _, ns = ...

local UI = ns.UI
local L = ns.L

local Button = {}
UI.Minimap = Button

local button

local function radius()
  return (Minimap:GetWidth() or 140) / 2 + 10
end

local function place()
  local angle = math.rad(ns.db.settings.minimap.angle or 225)
  local r = radius()
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- Ángulo del cursor respecto al centro del minimapa, en grados.
local function cursorAngle()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale() or 1
  return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function create()
  button = CreateFrame("Button", "ForeverProgressionGuideMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetPoint("CENTER")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("CENTER")
  button.icon:SetTexture(UI.LOGO)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then UI.Show("options") else UI.Toggle() end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      ns.db.settings.minimap.angle = cursorAngle()
      place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    UI.Tooltip(self, { L.TITLE, L.MINIMAP_TOOLTIP_LEFT, L.MINIMAP_TOOLTIP_RIGHT, L.MINIMAP_TOOLTIP_DRAG })
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Button.Refresh()
  if not (ns.db and Minimap) then return end
  if not button then create() end
  place()
  button:SetShown(not ns.db.settings.minimap.hide)
end

function Button.SetShown(shown)
  ns.db.settings.minimap.hide = not shown
  Button.Refresh()
end

function Button.Get() return button end

ns.On("PLAYER_LOGIN", Button.Refresh)
