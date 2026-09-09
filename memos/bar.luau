--!nonstrict

local connection = noctalia.state.get("connection") or {
  state = "unconfigured",
  sse = "disconnected",
}

local function indicatorColor()
  if connection.state == "connected" and connection.sse == "connected" then
    return "primary"
  elseif connection.state == "connecting" or connection.sse == "connecting" or connection.sse == "reconnecting" then
    return "secondary"
  end
  return "error"
end

local function statusText()
  if connection.state == "connected" then
    if connection.sse == "connected" then
      return noctalia.tr("status.connected")
    end
    return noctalia.tr("status.live_reconnecting")
  end
  return noctalia.tr("status." .. tostring(connection.state))
end

local function render()
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = "notes", size = 15, color = "on_surface" }),
    ui.box({ width = 7, height = 7, radius = 4, fill = indicatorColor() }),
    ui.label({ text = noctalia.tr("widget.label"), color = "on_surface" }),
  }))
  barWidget.setTooltip(noctalia.tr("widget.tooltip", { status = statusText() }))
end

noctalia.state.watch("connection", function(value)
  if type(value) == "table" then
    connection = value
    render()
  end
end)

function update()
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  noctalia.togglePanel("ovestokke/memos:panel")
end
