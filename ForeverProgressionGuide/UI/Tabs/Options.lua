-- Opciones. Se muestran como pestaña de la guía y también en la ventana de
-- opciones del juego (Opciones → AddOns), con el mismo contenido.
local _, ns = ...

local UI, C = ns.UI, ns.Compat
local L = ns.L

local LANGUAGES = { "auto", "es", "en" }

local function checkbox(parent, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb.label = UI.Label(cb, "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return cb
end

local function heading(parent)
  return UI.Label(parent, "GameFontNormal")
end

-- Construye los controles dentro de un marco cualquiera y devuelve su función de refresco.
function UI.BuildOptions(panel)
  local o = {}
  panel.controls = o

  o.languageTitle = heading(panel)
  o.languageTitle:SetPoint("TOPLEFT", 4, -4)
  o.languages = {}
  for i, lang in ipairs(LANGUAGES) do
    local b = UI.Button(panel, "", 110, function()
      ns.db.settings.language = lang
      ns.SetLanguage(lang)
      ns.Fire("LANGUAGE_CHANGED")
    end)
    b:SetPoint("TOPLEFT", 4 + (i - 1) * 116, -24)
    o.languages[lang] = b
  end

  o.generalTitle = heading(panel)
  o.generalTitle:SetPoint("TOPLEFT", 4, -64)
  o.minimap = checkbox(panel, function(on) UI.Minimap.SetShown(on) end)
  o.minimap:SetPoint("TOPLEFT", 0, -82)
  o.collect = checkbox(panel, function(on) ns.db.settings.collect = on end)
  o.collect:SetPoint("TOPLEFT", 0, -108)

  o.resetTitle = heading(panel)
  o.resetTitle:SetPoint("TOPLEFT", 4, -148)
  o.resetObjectives = UI.Button(panel, "", 230, function() ns.Objectives.ResetHidden() end)
  o.resetObjectives:SetPoint("TOPLEFT", 4, -168)
  o.resetWindow = UI.Button(panel, "", 230, function()
    ns.char.window = {}
    local frame = _G.ForeverProgressionGuideFrame
    if frame then
      frame:ClearAllPoints()
      frame:SetPoint("CENTER")
      frame:SetSize(840, 540)
    end
  end)
  o.resetWindow:SetPoint("LEFT", o.resetObjectives, "RIGHT", 8, 0)

  o.infoTitle = heading(panel)
  o.infoTitle:SetPoint("TOPLEFT", 4, -208)
  o.info = UI.Label(panel, "GameFontHighlightSmall")
  o.info:SetPoint("TOPLEFT", 4, -228)
  o.info:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

  o.creditsTitle = heading(panel)
  o.creditsTitle:SetPoint("TOPLEFT", 4, -268)
  o.credits = UI.Label(panel, "GameFontHighlightSmall")
  o.credits:SetPoint("TOPLEFT", 4, -288)
  o.credits:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

  return function()
    o.languageTitle:SetText(L.OPTIONS_LANGUAGE)
    o.languages.auto:SetText(L.OPTIONS_LANGUAGE_AUTO)
    o.languages.es:SetText("Español")
    o.languages.en:SetText("English")
    for lang, b in pairs(o.languages) do b:SetActive(ns.db.settings.language == lang) end

    o.generalTitle:SetText(L.OPTIONS_GENERAL)
    o.minimap.label:SetText(L.OPTIONS_MINIMAP)
    o.minimap:SetChecked(not ns.db.settings.minimap.hide)
    o.collect.label:SetText(L.OPTIONS_COLLECT)
    o.collect:SetChecked(ns.db.settings.collect)

    o.resetTitle:SetText(L.OPTIONS_RESET)
    o.resetObjectives:SetText(L.OPTIONS_RESET_OBJECTIVES)
    o.resetWindow:SetText(L.OPTIONS_RESET_WINDOW)

    local meta = ns.Data.Meta or {}
    local instances, quests = ns.Collector.Summary()
    o.infoTitle:SetText(L.OPTIONS_INFO)
    o.info:SetText(string.format(L.INFO, C.AddOnVersion(), meta.version or "?", meta.generated or "?",
      C.ClientBuild(), instances, quests, ns.Journal.Available() and L.YES or L.NO))

    -- Forever Companion pide que se cite su web; sus datos vienen a su vez de otras fuentes.
    local credits = meta.credits
    o.creditsTitle:SetText(L.OPTIONS_CREDITS)
    o.credits:SetText(credits and string.format(L.CREDITS_TEXT, credits.name, credits.url,
      table.concat(credits.sources or {}, ", "), credits.updatedAt or "?") or "")
  end
end

UI.RegisterTab({
  key = "options",
  Build = function(panel) panel.refresh = UI.BuildOptions(panel) end,
  Refresh = function(panel) panel.refresh() end,
})

-- Registro en la ventana de opciones del juego. Si este cliente no tiene la
-- API de Settings, las opciones siguen disponibles en la pestaña y con /wfg opciones.
local category

function UI.OpenGameOptions()
  if category and C.Has("Settings.OpenToCategory") then
    C.Call("Settings.OpenToCategory", category:GetID())
    return true
  end
  return false
end

ns.On("PLAYER_LOGIN", function()
  if not C.Has("Settings.RegisterCanvasLayoutCategory") then return end
  local panel = CreateFrame("Frame")
  panel:Hide()
  local refresh = UI.BuildOptions(panel)
  panel:SetScript("OnShow", refresh)
  ns.Listen("LANGUAGE_CHANGED", function() if panel:IsShown() then refresh() end end)
  category = C.Call("Settings.RegisterCanvasLayoutCategory", panel, L.TITLE)
  if category then C.Call("Settings.RegisterAddOnCategory", category) end
end)
