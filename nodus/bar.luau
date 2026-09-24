--!nonstrict

local connection = noctalia.state.get("connection") or { state = "loading" }
local function render()
  local color = if connection.state == "connected" then "primary" elseif connection.state == "loading" then "secondary" else "on_surface_variant"
  local layout = if barWidget.isVertical() then ui.column else ui.row
  barWidget.render(layout({ gap = 6, align = "center" }, {
    ui.glyph({ name = "notes", size = 17, color = color }),
    ui.label({ text = "Nodus", color = "on_surface" }),
    ui.box({ width = 6, height = 6, radius = 3, fill = color }),
  }))
  barWidget.setTooltip("Nodus: " .. tostring(connection.state))
end
noctalia.state.watch("connection", function(value)
  if type(value) == "table" then connection = value; render() end
end)
function update()
  noctalia.setUpdateInterval(60000)
  render()
end
function onClick()
  noctalia.togglePanel("ovestokke/nodus:panel")
end
