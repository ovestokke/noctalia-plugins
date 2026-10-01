-- Run from the repository root: lua tools/test_nodus_bar.lua
-- bar.luau deliberately uses syntax shared by Lua and Luau; no source rewriting.
local function scenario(initial, dark)
  local displayed, watch, interval, opened
  local function expected(connected)
    local stem = connected and "assets/nodus-icon" or "assets/nodus-icon-grayscale"
    return stem .. (dark and "-dark.png" or "-light.png")
  end
  local env = setmetatable({
    noctalia = {
      state = {
        get = function(key) assert(key == "connection"); return initial end,
        watch = function(key, callback) assert(key == "connection"); watch = callback end,
      },
      isDarkMode = function() return dark end,
      setUpdateInterval = function(ms) interval = ms end,
      togglePanel = function(id) opened = id end,
    },
    barWidget = {
      setText = function(text) assert(text == "") end,
      setGlyph = function(glyph) assert(glyph == "") end,
      setImage = function(path, watching, width, height)
        assert(watching == false)
        assert(width == 22 and height == 22) -- square in either bar orientation
        displayed = path
      end,
      setTooltip = function(text)
        assert(text:find("Nodus: ", 1, true) == 1)
        assert(text:find("Click to open notes", 1, true))
      end,
      -- No render/ui mock: adding text, count, or a status dot fails this test.
    },
  }, { __index = _G })
  assert(loadfile("nodus/bar.luau", "t", env))()
  env.update()
  assert(interval == 1000)
  assert(displayed == expected(initial and initial.state == "connected"))
  for _, state in ipairs({"connected", "offline", "connected", "loading", "disconnected",
      "busy", "rate_limited", "error", "unpaired", "unknown", "connected"}) do
    watch({state = state})
    assert(displayed == expected(state == "connected"), state)
  end
  watch(nil)
  assert(displayed == expected(false))
  watch({state = "connected"})
  assert(displayed == expected(true))
  dark = not dark
  env.update()
  assert(displayed == expected(true))
  watch(false)
  assert(displayed == expected(false))
  dark = not dark
  env.update()
  assert(displayed == expected(false))
  env.onClick()
  assert(opened == "ovestokke/nodus:panel")
end

for _, dark in ipairs({true, false}) do
  scenario(nil, dark)
  scenario({state = "connected"}, dark)
  scenario({state = "offline"}, dark)
end
print("Nodus bar: states, theme changes, sizing, icon-only output, tooltip and click passed")
