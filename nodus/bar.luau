--!nonstrict

local connection = noctalia.state.get("connection") or { state = "loading" }
local function render()
  local icon = "assets/nodus-icon-grayscale.png"
  if connection.state == "connected" then icon = "assets/nodus-icon.png" end
  barWidget.setText("")
  barWidget.setGlyph("")
  barWidget.setImage(icon, false, 22, 22)
  barWidget.setTooltip("Nodus: " .. tostring(connection.state) .. "\nClick to open notes")
end
noctalia.state.watch("connection", function(value)
  connection = { state = "loading" }
  if type(value) == "table" then connection = value end
  render()
end)
function update()
  noctalia.setUpdateInterval(60000)
  render()
end
function onClick()
  noctalia.togglePanel("ovestokke/nodus:panel")
end
