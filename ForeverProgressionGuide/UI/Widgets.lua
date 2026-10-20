-- Piezas de interfaz reutilizables: textos, botones, listas con desplazamiento.
local _, ns = ...

local UI = {}
ns.UI = UI

UI.CATEGORY_COLORS = { recommended = "40ff40", reward = "66bbff", optional = "9d9d9d", too_early = "ff5050", unverified = "ffd100", unavailable = "6e6e6e" }
UI.CONFIDENCE_COLORS = { high = "40ff40", medium = "ffd100", low = "ff9933", none = "9d9d9d" }

function UI.Color(hex, text)
  return "|cff" .. hex .. tostring(text) .. "|r"
end

function UI.Label(parent, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

function UI.Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 100, 22)
  b:SetText(text or "")
  if onClick then b:SetScript("OnClick", onClick) end
  return b
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
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(1, 1, 1, 0.04)
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
  local menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
  if menu.SetBackdrop then
    menu:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.05, 0.08, 0.15, 0.97)
  end
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
