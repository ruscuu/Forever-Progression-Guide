-- Ventana principal: cabecera del personaje, selector de idioma y pestañas.
local _, ns = ...

local UI = ns.UI
local L = ns.L

UI.LOGO = "Interface\\AddOns\\" .. ns.name .. "\\Media\\Logo"

local tabs, order = {}, {}
UI.tabs = tabs
local frame, current, currentArg

function UI.RegisterTab(def)
  tabs[def.key] = def
  order[#order + 1] = def.key
end

local LANGUAGE_CYCLE = { auto = "es", es = "en", en = "auto" }
local HEADER_HEIGHT = 58
local NAV_WIDTH = 140

-- Icono de cada pestaña en la barra lateral.
local TAB_ICONS = {
  progress = "Interface\\Icons\\INV_Misc_Book_09",
  dungeons = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  gear = "Interface\\Icons\\INV_Chest_Chain_05",
  quests = "Interface\\Icons\\INV_Misc_Note_01",
  professions = "Interface\\Icons\\Trade_BlackSmithing",
  search = "Interface\\Icons\\INV_Misc_Spyglass_03",
  options = "Interface\\Icons\\INV_Misc_Gear_01",
}

local function languageLabel()
  local setting = ns.db.settings.language
  if setting == "auto" then return "Auto (" .. string.upper(ns.lang) .. ")" end
  return string.upper(setting)
end

local ROLE_KEYS = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" }

local function refreshFilter()
  local F = ns.ClassFilter
  local selection = F.Current()

  local classOptions = { { text = L.FILTER_MY_CHARACTER, value = "reset", selected = selection.isPlayer } }
  for _, c in ipairs(F.Classes()) do
    classOptions[#classOptions + 1] = { text = c.name, value = c.classID, selected = not selection.isPlayer and c.classID == selection.classID }
  end
  frame.classSelector:SetOptions(classOptions, function(value)
    if value == "reset" then F.Reset() else F.SetClass(value) end
  end)
  frame.classSelector:SetText(selection.className)

  local specs = F.Specs(selection.classID)
  frame.specSelector.button:SetShown(#specs > 0)
  local specOptions = { { text = L.FILTER_ALL_SPECS, value = F.ALL_SPECS, selected = selection.specID == F.ALL_SPECS } }
  for _, s in ipairs(specs) do
    local role = ROLE_KEYS[s.role] and (" (" .. L[ROLE_KEYS[s.role]] .. ")") or ""
    specOptions[#specOptions + 1] = { text = s.name .. role, value = s.specID, selected = s.specID == selection.specID }
  end
  frame.specSelector:SetOptions(specOptions, F.SetSpec)
  frame.specSelector:SetText(selection.specName or L.FILTER_ALL_SPECS)
end

local function refreshHeader()
  local p = ns.Compat.Player()
  local className = p.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[p.class]) or p.class or "?"
  frame.title:SetText(L.TITLE)
  frame.subtitle:SetText(string.format(L.HEADER_CHARACTER, p.name or "?", p.level, className))
  frame.language:SetText(languageLabel())
  for _, key in ipairs(order) do frame.nav[key]:SetText(L["TAB_" .. string.upper(key)]) end
  refreshFilter()
end

local function savePosition()
  local point, _, relativePoint, x, y = frame:GetPoint()
  ns.char.window.point = { point, relativePoint, x, y }
  ns.char.window.size = { frame:GetWidth(), frame:GetHeight() }
end

local function create()
  frame = CreateFrame("Frame", "ForeverProgressionGuideFrame", UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  local size = ns.char.window.size
  frame:SetSize(size and size[1] or 840, size and size[2] or 540)
  local pos = ns.char.window.point
  if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end
  local theme = UI.THEME
  UI.Box(frame, theme.background, theme.border)

  -- Cabecera: franja con una línea dorada debajo.
  local header = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(HEADER_HEIGHT)
  UI.Paint(header, theme.header)
  local rule = frame:CreateTexture(nil, "BORDER")
  rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
  rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
  rule:SetHeight(1)
  UI.Paint(rule, { theme.accent[1], theme.accent[2], theme.accent[3], 0.6 })

  -- Barra lateral de navegación.
  local sidebar = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  sidebar:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT - 2)
  sidebar:SetPoint("BOTTOMLEFT", 1, 1)
  sidebar:SetWidth(NAV_WIDTH + 16)
  UI.Paint(sidebar, theme.panel)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() savePosition() end)
  frame:SetResizable(true)
  if frame.SetResizeBounds then frame:SetResizeBounds(700, 440) elseif frame.SetMinResize then frame:SetMinResize(700, 440) end
  table.insert(UISpecialFrames, "ForeverProgressionGuideFrame")

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

  frame.logo = frame:CreateTexture(nil, "ARTWORK")
  frame.logo:SetSize(44, 44)
  frame.logo:SetPoint("TOPLEFT", 10, -7)
  frame.logo:SetTexture(UI.LOGO)

  frame.title = UI.Label(frame, "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame.logo, "TOPRIGHT", 8, -6)
  frame.subtitle = UI.Label(frame, "GameFontHighlightSmall")
  frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)

  frame.language = UI.Button(frame, "", 90, function()
    ns.db.settings.language = LANGUAGE_CYCLE[ns.db.settings.language] or "auto"
    ns.SetLanguage(ns.db.settings.language)
    ns.Fire("LANGUAGE_CHANGED")
  end)
  frame.language:SetPoint("TOPRIGHT", -36, -18)

  -- Clase y especialización con las que se filtra la guía (por defecto, las del personaje).
  frame.specSelector = UI.Selector(frame, 140)
  frame.specSelector.button:SetPoint("RIGHT", frame.language, "LEFT", -8, 0)
  frame.classSelector = UI.Selector(frame, 120)
  frame.classSelector.button:SetPoint("RIGHT", frame.specSelector.button, "LEFT", -4, 0)

  frame.nav = {}
  for i, key in ipairs(order) do
    local b = UI.Button(frame, "", NAV_WIDTH, function() UI.Select(key) end)
    b:SetHeight(30)
    b:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT - 10 - (i - 1) * 34)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 5, 0)
    b.icon:SetTexture(TAB_ICONS[key] or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.label:SetJustifyH("LEFT")
    frame.nav[key] = b
  end

  frame.content = CreateFrame("Frame", nil, frame)
  frame.content:SetPoint("TOPLEFT", NAV_WIDTH + 30, -HEADER_HEIGHT - 12)
  frame.content:SetPoint("BOTTOMRIGHT", -14, 24)

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
    frame.nav[k]:SetActive(k == key)
  end
  current, currentArg = key, arg
  refreshHeader()
  local meta = ns.Data.Meta or {}
  local credits = meta.credits and (" · " .. string.format(L.FOOTER_CREDITS, meta.credits.name)) or ""
  frame.footer:SetText(string.format(L.FOOTER, ns.Compat.AddOnVersion(), meta.version or "?", ns.Compat.ClientBuild()) .. credits)
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

for _, message in ipairs({ "FILTER_CHANGED", "LANGUAGE_CHANGED", "OBJECTIVES_CHANGED", "JOURNAL_LOOT_UPDATED",
                           "INSTANCE_OBSERVED", "CLIENT_DATA_RECEIVED" }) do
  ns.Listen(message, refreshIfShown)
end
ns.On("PLAYER_LEVEL_UP", refreshIfShown)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() if UI.IsShown("gear") or UI.IsShown("progress") then refreshIfShown() end end)
