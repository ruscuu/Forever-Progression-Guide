-- Configuración de luacheck para el addon (Lua 5.1, como el cliente de WoW).
std = "lua51"
max_line_length = false
unused_args = false

-- Variables globales que el addon define a propósito.
globals = {
  "WoWForeverGuideDB",
  "WoWForeverGuideCharDB",
  "SLASH_WOWFOREVERGUIDE1",
  "SLASH_WOWFOREVERGUIDE2",
  "WoWForeverGuide_OnAddonCompartmentClick",
  SlashCmdList = { fields = { "WOWFOREVERGUIDE" } },
}

-- API del cliente que se usa directamente (el resto pasa por ns.Compat.Call).
read_globals = {
  "C_Map", "C_Timer", "CreateFrame", "Enum", "GameTooltip", "GetBuildInfo", "GetInstanceInfo",
  "GetInventoryItemLink", "GetInventoryItemQuality", "GetLocale", "IsInInstance",
  "LOCALIZED_CLASS_NAMES_MALE", "UIParent", "UISpecialFrames", "UiMapPoint", "UnitClass",
  "UnitFactionGroup", "UnitLevel", "UnitName", "time",
}
