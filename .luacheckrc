-- Configuración de luacheck para el addon (Lua 5.1, como el cliente de WoW).
std = "lua51"
max_line_length = false
unused_args = false

-- Variables globales que el addon define a propósito.
globals = {
  "ForeverProgressionGuideDB",
  "ForeverProgressionGuideCharDB",
  "SLASH_FOREVERPROGRESSIONGUIDE1",
  "SLASH_FOREVERPROGRESSIONGUIDE2",
  "ForeverProgressionGuide_OnAddonCompartmentClick",
  SlashCmdList = { fields = { "FOREVERPROGRESSIONGUIDE" } },
}

-- API del cliente que se usa directamente (el resto pasa por ns.Compat.Call).
read_globals = {
  "C_Map", "C_Timer", "CreateFrame", "Enum", "GameTooltip", "GetBuildInfo", "GetInstanceInfo",
  "GetCursorPosition", "GetInventoryItemLink", "GetInventoryItemTexture", "Minimap", "GetInventoryItemQuality", "GetLocale", "IsInInstance",
  "LOCALIZED_CLASS_NAMES_MALE", "UIParent", "UISpecialFrames", "UiMapPoint", "UnitClass",
  "UnitFactionGroup", "UnitLevel", "UnitName", "time",
}
