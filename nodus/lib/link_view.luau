-- Existing Noctalia labels have no inline link callbacks. Keep the original
-- text node and provide native URL actions rather than interpreting its markup.
local Links = require("./links.luau")
local LinkView = {}

function LinkView.open(url)
  -- Revalidate at activation, even though the detector already checked it.
  if not Links.isSafeHttpUrl(url) then return false end
  if not noctalia.commandExists("xdg-open") or not noctalia.runAsync({ "xdg-open", url }) then
    noctalia.notifyError("Nodus", "Could not open the link. Check your default browser.")
    return false
  end
  return true
end

function LinkView.render(text, content)
  local urls = {}
  for _, segment in ipairs(Links.segments(text)) do
    if segment.href then table.insert(urls, segment.href) end
  end
  if #urls == 0 then return content end
  if #urls == 1 and string.match(text, "^%s*(.-)%s*$") == urls[1] then
    local url = urls[1]
    return ui.row({ gap = 6, align = "start", flexGrow = 1,
      onClick = function() LinkView.open(url) end }, {
      content,
      ui.glyph({ name = "external-link", size = 14, color = "primary" }),
    })
  end
  local children = { content }
  for index, value in ipairs(urls) do
    local url = value
    table.insert(children, ui.row({ key = "link-" .. tostring(index), gap = 6, paddingV = 3, align = "start",
      onClick = function() LinkView.open(url) end }, {
      ui.glyph({ name = "external-link", size = 13, color = "primary" }),
      ui.label({ text = url, fontSize = 12, color = "primary", flexGrow = 1 }),
    }))
  end
  return ui.column({ gap = 4, flexGrow = 1 }, children)
end

return LinkView
