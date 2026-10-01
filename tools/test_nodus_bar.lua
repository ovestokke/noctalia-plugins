-- Run from the repository root: lua tools/test_nodus_bar.lua
-- bar.luau deliberately uses syntax shared by Lua and Luau; no source rewriting.
local colored = "assets/nodus-icon.png"
local grayscale = "assets/nodus-icon-grayscale.png"

local function scenario(initial)
  local displayed, watch, interval, opened
  local env = setmetatable({
    noctalia = {
      state = {
        get = function(key) assert(key == "connection"); return initial end,
        watch = function(key, callback) assert(key == "connection"); watch = callback end,
      },
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
  assert(interval == 60000)
  assert(displayed == (initial and initial.state == "connected" and colored or grayscale))
  for _, state in ipairs({"connected", "offline", "connected", "loading", "disconnected",
      "busy", "rate_limited", "error", "unpaired", "unknown", "connected"}) do
    watch({state = state})
    assert(displayed == (state == "connected" and colored or grayscale), state)
  end
  watch(nil)
  assert(displayed == grayscale)
  watch({state = "connected"})
  assert(displayed == colored)
  watch(false)
  assert(displayed == grayscale)
  env.onClick()
  assert(opened == "ovestokke/nodus:panel")
end

scenario(nil)
scenario({state = "connected"})
scenario({state = "offline"})
print("Nodus bar: initial states, transitions, image sizing, icon-only output, tooltip and click passed")
