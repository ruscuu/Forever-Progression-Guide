-- Ventana principal: cabecera del personaje, selector de idioma y pestañas.
local _, ns = ...

local UI = ns.UI
local L = ns.L

local tabs, order = {}, {}
UI.tabs = tabs
local frame, current, currentArg

function UI.RegisterTab(def)
  tabs[def.key] = def
  order[#order + 1] = def.key
end

local LANGUAGE_CYCLE = { auto = "es", es = "en", en = "auto" }

local function languageLabel()
  local setting = ns.db.settings.language
  if setting == "auto" then return "Auto (" .. string.upper(ns.lang) .. ")" end
  return string.upper(setting)
end

local function refreshHeader()
  local p = ns.Compat.Player()
  local className = p.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.class]) or p.class or "?"
  frame.title:SetText(L.TITLE)
  frame.subtitle:SetText(string.format(L.HEADER_CHARACTER, p.name or "?", p.level, className))
  frame.language:SetText(languageLabel())
  for _, key in ipairs(order) do frame.nav[key]:SetText(L["TAB_" .. string.upper(key)]) end
end

local function savePosition()
  local point, _, relativePoint, x, y = frame:GetPoint()
  ns.char.window.point = { point, relativePoint, x, y }
  ns.char.window.size = { frame:GetWidth(), frame:GetHeight() }
end

local function create()
  frame = CreateFrame("Frame", "WoWForeverGuideFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  local size = ns.char.window.size
  frame:SetSize(size and size[1] or 840, size and size[2] or 540)
  local pos = ns.char.window.point
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() savePosition() end)
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(700, 440) elseif frame.SetMinResize then frame:SetMinResize(700, 440) end
  table.insert(UISpecialFrames, "WoWForeverGuideFrame")

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    savePosition()
    UI.Select(current, currentArg)
  end)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  frame.title = UI.Label(frame, "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", 16, -14)
  frame.subtitle = UI.Label(frame, "GameFontHighlightSmall")
  frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)

  frame.language = UI.Button(frame, "", 90, function()
    ns.db.settings.language = LANGUAGE_CYCLE[ns.db.settings.language] or "auto"
    ns.SetLanguage(ns.db.settings.language)
    ns.Fire("LANGUAGE_CHANGED")
  end)
  frame.language:SetPoint("TOPRIGHT", -36, -12)

  frame.nav = {}
  for i, key in ipairs(order) do
    local b = UI.Button(frame, "", 130, function() UI.Select(key) end)
    b:SetPoint("TOPLEFT", 12, -56 - (i - 1) * 26)
    frame.nav[key] = b
  end

  frame.content = CreateFrame("Frame", nil, frame)
  frame.content:SetPoint("TOPLEFT", 152, -56)
  frame.content:SetPoint("BOTTOMRIGHT", -14, 22)

  for _, key in ipairs(order) do
    local panel = CreateFrame("Frame", nil, frame.content)
    panel:SetAllPoints()
    panel:Hide()
    tabs[key].panel = panel
    ns.Safe("Build:" .. key, tabs[key].Build, panel)
  end

  frame.footer = UI.Label(frame, "GameFontDisableSmall")
  frame.footer:SetPoint("BOTTOMLEFT", 16, 8)
end

function UI.Select(key, arg)
  if not frame then return end
  key = key or current or order[1]
  for k, def in pairs(tabs) do
    def.panel:SetShown(k == key)
    frame.nav[k]:SetEnabled(k ~= key)
  end
  current, currentArg = key, arg
  refreshHeader()
  local meta = ns.Data.Meta or {}
  frame.footer:SetText(string.format(L.FOOTER, ns.Compat.AddOnVersion(), meta.version or "?", ns.Compat.ClientBuild()))
  if tabs[key].Refresh then ns.Safe("Refresh:" .. key, tabs[key].Refresh, tabs[key].panel, arg) end
end

function UI.Show(key, arg)
  if not frame then create() end
  frame:Show()
  UI.Select(key, arg)
end

function UI.Toggle()
  if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

function UI.IsShown(key)
  return frame and frame:IsShown() and (not key or current == key)
end

local function refreshIfShown()
  if frame and frame:IsShown() then UI.Select(current, currentArg) end
end

for _, message in ipairs({ "LANGUAGE_CHANGED", "OBJECTIVES_CHANGED", "JOURNAL_LOOT_UPDATED", "INSTANCE_OBSERVED" }) do
  ns.Listen(message, refreshIfShown)
end
ns.On("PLAYER_LEVEL_UP", refreshIfShown)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() if UI.IsShown("gear") or UI.IsShown("progress") then refreshIfShown() end end)
