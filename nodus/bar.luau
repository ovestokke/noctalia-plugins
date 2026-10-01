--!nonstrict

local connection = noctalia.state.get("connection") or { state = "loading" }
local currentIcon = nil
local function render()
  local stem = "assets/nodus-icon-grayscale"
  if connection.state == "connected" then stem = "assets/nodus-icon" end
  local theme = "light"
  if noctalia.isDarkMode() then theme = "dark" end
  local icon = stem .. "-" .. theme .. ".png"
  if icon ~= currentIcon then
    barWidget.setText("")
    barWidget.setGlyph("")
    barWidget.setImage(icon, false, 22, 22)
    currentIcon = icon
  end
  barWidget.setTooltip("Nodus: " .. tostring(connection.state) .. "\nClick to open notes")
end
noctalia.state.watch("connection", function(value)
  connection = { state = "loading" }
  if type(value) == "table" then connection = value end
  render()
end)
function update()
  -- Also follow theme changes while the connection state stays unchanged.
  noctalia.setUpdateInterval(1000)
  render()
end
function onClick()
  noctalia.togglePanel("ovestokke/nodus:panel")
end
