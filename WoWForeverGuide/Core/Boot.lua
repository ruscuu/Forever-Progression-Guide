-- Comandos de barra y punto de entrada del compartimento de addons.
local _, ns = ...

local L = ns.L
local PREFIX = "|cffffd100Forever Guide:|r "

local function say(text) print(PREFIX .. text) end

local COMMANDS = {}

COMMANDS.es = function() ns.db.settings.language = "es" end
COMMANDS.en = function() ns.db.settings.language = "en" end
COMMANDS.auto = function() ns.db.settings.language = "auto" end
for _, lang in ipairs({ "es", "en", "auto" }) do
  local set = COMMANDS[lang]
  COMMANDS[lang] = function()
    set()
    ns.SetLanguage(ns.db.settings.language)
    ns.Fire("LANGUAGE_CHANGED")
    say(string.format(L.LANGUAGE_SET, lang))
  end
end

COMMANDS.collect = function(arg)
  ns.db.settings.collect = arg ~= "off"
  say(ns.db.settings.collect and L.COLLECT_ON or L.COLLECT_OFF)
end

COMMANDS.info = function()
  local meta = ns.Data.Meta or {}
  local instances, quests = ns.Collector.Summary()
  say(string.format(L.INFO, ns.Compat.AddOnVersion(), meta.version or "?", meta.generated or "?",
    ns.Compat.ClientBuild(), instances, quests, ns.Journal.Available() and L.YES or L.NO))
end

COMMANDS.errors = function()
  if #ns.errors == 0 then return say(L.ERRORS_NONE) end
  say(string.format(L.ERRORS_HEADER, #ns.errors))
  for _, e in ipairs(ns.errors) do print("  " .. e) end
end

COMMANDS.help = function() say(L.SLASH_HELP) end

SLASH_WOWFOREVERGUIDE1 = "/wfg"
SLASH_WOWFOREVERGUIDE2 = "/guia"
SlashCmdList.WOWFOREVERGUIDE = function(input)
  local cmd, arg = string.match(string.lower(input or ""), "^%s*(%S*)%s*(%S*)")
  if cmd == "" then return ns.UI.Toggle() end
  local fn = COMMANDS[cmd] or COMMANDS.help
  fn(arg)
end

function WoWForeverGuide_OnAddonCompartmentClick()
  ns.UI.Toggle()
end
