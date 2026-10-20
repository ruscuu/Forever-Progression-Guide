-- Piezas de interfaz reutilizables: textos, botones, listas con desplazamiento.
local _, ns = ...

local UI = {}
ns.UI = UI

UI.CATEGORY_COLORS = { recommended = "40ff40", reward = "66bbff", optional = "9d9d9d", too_early = "ff5050", unverified = "ffd100", unavailable = "6e6e6e" }
UI.CONFIDENCE_COLORS = { high = "40ff40", medium = "ffd100", low = "ff9933", none = "9d9d9d" }

-- Paleta de la guía (RGBA): fondo azul noche y acentos dorados, como el logo.
UI.THEME = {
  background = { 0.05, 0.06, 0.09, 0.97 },
  border = { 0.24, 0.27, 0.35, 1 },
  header = { 0.09, 0.12, 0.19, 1 },
  panel = { 0.08, 0.10, 0.15, 0.95 },
  stripe = { 1, 1, 1, 0.035 },
  accent = { 0.95, 0.76, 0.25, 1 },
  button = { 0.13, 0.16, 0.23, 1 },
  buttonHover = { 0.19, 0.23, 0.32, 1 },
  buttonActive = { 0.26, 0.21, 0.08, 1 },
  buttonDisabled = { 0.10, 0.11, 0.14, 1 },
  text = { 0.92, 0.92, 0.92 },
  textActive = { 1, 0.82, 0.2 },
  textDisabled = { 0.45, 0.45, 0.45 },
}

-- Colorea una textura con un color de la paleta.
function UI.Paint(texture, color)
  texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- Rectángulo de fondo con borde de 1 px.
function UI.Box(frame, fill, border)
  local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  edge:SetAllPoints()
  UI.Paint(edge, border or UI.THEME.border)
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  UI.Paint(bg, fill or UI.THEME.panel)
  return bg, edge
end

function UI.Color(hex, text)
  return "|cff" .. hex .. tostring(text) .. "|r"
end

function UI.Label(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

local function paintButton(b)
  local t = UI.THEME
  local fill = (b.active and t.buttonActive) or (not b:IsEnabled() and t.buttonDisabled) or (b.hover and t.buttonHover) or t.button
  UI.Paint(b.bg, fill)
  b.accent:SetShown(b.active and true or false)
  local color = (b.active and t.textActive) or (b:IsEnabled() and t.text) or t.textDisabled
  b.label:SetTextColor(color[1], color[2], color[3])
end

-- Botón plano con el estilo de la guía. Además de SetEnabled (no disponible),
-- admite SetActive para marcar la opción seleccionada (pestaña, modo, idioma).
function UI.Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 100, 22)
  b.bg = UI.Box(b, UI.THEME.button)
  b.accent = b:CreateTexture(nil, "ARTWORK")
  b.accent:SetPoint("BOTTOMLEFT", 1, 1)
  b.accent:SetPoint("BOTTOMRIGHT", -1, 1)
  b.accent:SetHeight(2)
  UI.Paint(b.accent, UI.THEME.accent)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", 6, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  b.label:SetWordWrap(false)
  b:SetFontString(b.label)

  local setEnabled = b.SetEnabled
  b.SetEnabled = function(self, enabled)
    setEnabled(self, enabled)
    paintButton(self)
  end
  function b:SetActive(active)
    self.active = active and true or nil
    paintButton(self)
  end
  b:SetScript("OnEnter", function(self) self.hover = true paintButton(self) end)
  b:SetScript("OnLeave", function(self) self.hover = nil paintButton(self) GameTooltip:Hide() end)
  b:SetText(text or "")
  if onClick then b:SetScript("OnClick", onClick) end
  paintButton(b)
  return b
end

-- Título de sección con una línea dorada debajo.
function UI.Header(parent, width)
  local fs = UI.Label(parent, "GameFontNormal")
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
  line:SetWidth(width or 220)
  UI.Paint(line, { 0.95, 0.76, 0.25, 0.5 })
  fs.line = line
  return fs
end

function UI.Tooltip(owner, lines, link)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if link then
    GameTooltip:SetHyperlink(link)
  else
    for i, line in ipairs(lines) do
      if i == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
  end
  GameTooltip:Show()
end

local function hideTooltip() GameTooltip:Hide() end

local function defaultRow(content, list)
  local row = CreateFrame("Button", nil, content)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.left = UI.Label(row, "GameFontHighlight")
  row.left:SetPoint("LEFT", 6, 0)
  row.left:SetPoint("RIGHT", -60, 0)
  row.left:SetWordWrap(false)
  row.right = UI.Label(row, "GameFontHighlightSmall", "RIGHT")
  row.right:SetPoint("RIGHT", -6, 0)
  row:SetScript("OnClick", function(self) if list.onClick then list.onClick(self.item, self) end end)
  row:SetScript("OnEnter", function(self) if list.onEnter then list.onEnter(self.item, self) end end)
  row:SetScript("OnLeave", hideTooltip)
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  UI.Paint(row.stripe, UI.THEME.stripe)
  return row
end

-- Fila con icono a la izquierda (objetos, misiones).
function UI.IconRow(content, list)
  local row = defaultRow(content, list)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(list.rowHeight - 4, list.rowHeight - 4)
  row.icon:SetPoint("LEFT", 4, 0)
  row.left:ClearAllPoints()
  row.left:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.left:SetPoint("RIGHT", -110, 0)
  return row
end

-- Lista con desplazamiento que reutiliza filas. buildRow es opcional.
function UI.List(parent, rowHeight, buildRow)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)

  local list = { scroll = scroll, content = content, rows = {}, rowHeight = rowHeight or 20 }

  -- Coloca la lista dentro de su contenedor dejando sitio a la barra de desplazamiento.
  function list:SetPoints(topLeftX, topLeftY, bottomRightX, bottomRightY)
    scroll:SetPoint("TOPLEFT", topLeftX, topLeftY)
    scroll:SetPoint("BOTTOMRIGHT", bottomRightX - 24, bottomRightY)
  end

  function list:SetData(items, render)
    for i, item in ipairs(items) do
      local row = self.rows[i]
      if not row then
        row = (buildRow or defaultRow)(content, self)
        row:SetHeight(self.rowHeight)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
        row:SetPoint("RIGHT", content, "RIGHT")
        self.rows[i] = row
      end
      row.item = item
      if type(row.stripe) == "table" then row.stripe:SetShown(i % 2 == 0) end
      render(row, item)
      row:Show()
    end
    for i = #items + 1, #self.rows do self.rows[i]:Hide() end
    content:SetHeight(math.max(1, #items * self.rowHeight))
  end

  return list
end

-- Desplegable sencillo. Se construye a mano porque el menú desplegable de
-- Blizzard cambió en el motor 12.0 y no es seguro que exista en Forever.
local ITEM_HEIGHT = 20

function UI.Selector(parent, width)
  local button = UI.Button(parent, "", width)
  local menu = CreateFrame("Frame", nil, button)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
  UI.Box(menu, UI.THEME.background, UI.THEME.accent)
  menu:Hide()

  local selector = { button = button, menu = menu, items = {}, options = {} }

  function selector:SetOptions(options, onSelect)
    self.options, self.onSelect = options, onSelect
  end

  function selector:SetText(text) button:SetText(text) end

  function selector:Open()
    for i, option in ipairs(self.options) do
      local item = self.items[i]
      if not item then
        item = CreateFrame("Button", nil, menu)
        item:SetHeight(ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 6, -4 - (i - 1) * ITEM_HEIGHT)
        item:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        item.label = UI.Label(item, "GameFontHighlightSmall")
        item.label:SetPoint("LEFT", 4, 0)
        item:SetScript("OnClick", function(clicked)
          menu:Hide()
          if selector.onSelect then selector.onSelect(clicked.value) end
        end)
        self.items[i] = item
      end
      item.value = option.value
      item.label:SetText(option.selected and UI.Color("ffd100", option.text) or option.text)
      item:Show()
    end
    for i = #self.options + 1, #self.items do self.items[i]:Hide() end
    menu:SetSize(math.max(width, 180), #self.options * ITEM_HEIGHT + 8)
    menu:Show()
  end

  button:SetScript("OnClick", function()
    if menu:IsShown() then menu:Hide() else selector:Open() end
  end)
  return selector
end

-- Texto largo con desplazamiento.
function UI.TextPanel(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  local text = UI.Label(content, "GameFontHighlight")
  text:SetPoint("TOPLEFT", 4, -4)
  text:SetPoint("RIGHT", content, "RIGHT", -4, 0)
  text:SetSpacing(2)

  local panel = { scroll = scroll }
  function panel:SetText(value)
    content:SetWidth(math.max(scroll:GetWidth(), 100))
    text:SetText(value)
    content:SetHeight(text:GetStringHeight() + 12)
    scroll:SetVerticalScroll(0)
  end
  scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
  return panel
end
