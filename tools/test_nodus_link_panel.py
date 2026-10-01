#!/usr/bin/env python3
"""Exercise the actual Luau panel with stub UI/browser APIs. Pass the Luau CLI path."""

from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    text = (ROOT / path).read_text()
    assert "]====]" not in text
    return "[====[" + text + "]====]"


harness = 'local sources = {\n' + ',\n'.join(
    f'["{key}"] = {source(path)}' for key, path in {
        "./links.luau": "nodus/lib/links.luau",
        "./lib/link_view.luau": "nodus/lib/link_view.luau",
        "panel": "nodus/panel.luau",
    }.items()
) + r'''
}
local function scenario(note, expectedUrls)
  local tree, calls, commands, watchers = nil, {}, {}, {}
  local values = {
    connection = {state = "connected"},
    notes = {items = {{id = note.id, kind = note.kind, title = "Test", state = "live"}}, counts = {}},
  }
  local env = setmetatable({}, {__index = getfenv()})
  env.noctalia = {
    state = {
      get = function(key) return values[key] end,
      watch = function(key, callback) watchers[key] = callback end,
      set = function(key, value) assert(key == "command"); table.insert(commands, value) end,
    },
    tr = function(key) return key end,
    getConfig = function() return nil end,
    commandExists = function(name) assert(name == "xdg-open"); return true end,
    runAsync = function(argv)
      assert(type(argv) == "table" and #argv == 2 and argv[1] == "xdg-open")
      table.insert(calls, argv[2]); return true
    end,
    notifyError = function() error("Unexpected open error") end,
  }
  env.ui = setmetatable({}, {__index = function(_, kind)
    return function(props, children) return {kind = kind, props = props, children = children or {}} end
  end})
  env.panel = {render = function(node) tree = node end, close = function() end}
  local loaded = {}
  local function load(name)
    local chunk = assert(loadstring(assert(sources[name]), name))
    setfenv(chunk, env)
    return chunk()
  end
  env.require = function(name)
    if not loaded[name] then loaded[name] = load(name) end
    return loaded[name]
  end
  local function find(node, predicate)
    if predicate(node) then return node end
    for _, child in ipairs(node.children) do
      local result = find(child, predicate)
      if result then return result end
    end
  end
  load("panel")
  env.onOpen({})
  local row = assert(find(tree, function(n) return n.props.key == "note-" .. note.id end))
  row.props.onClick()
  watchers.selected(note)
  commands = {}
  assert(#calls == 0, "render navigated")
  local actions = {}
  local function collect(node, ancestorClick)
    if node.kind == "row" and node.props.onClick then
      for _, child in ipairs(node.children) do
        if child.kind == "glyph" and child.props.name == "external-link" then
          assert(not ancestorClick, "link has an actionable ancestor")
          table.insert(actions, node)
        end
      end
    end
    for _, child in ipairs(node.children) do collect(child, ancestorClick or node.props.onClick ~= nil) end
  end
  collect(tree, false)
  assert(#actions == #expectedUrls)
  for _, action in ipairs(actions) do action.props.onClick() end
  assert(#commands == 0, "link toggled/opened/edited a note")
  table.sort(calls); table.sort(expectedUrls)
  for i, url in ipairs(expectedUrls) do assert(calls[i] == url) end
  if note.kind == "checklist" then
    local checked = assert(find(tree, function(n) return n.kind == "markdown" end))
    assert(string.sub(checked.props.text, 1, 2) == "~~", "completed style lost")
    local checkbox = assert(find(tree, function(n) return n.kind == "button" and n.props.glyph == "square" end))
    local before = #calls
    checkbox.props.onClick()
    assert(#commands == 1 and commands[1].action == "checked" and commands[1].checked == true)
    assert(#calls == before, "checkbox opened a link")
  else
    assert(find(tree, function(n) return n.kind == "label" and n.props.text == note.text end), "raw note text changed")
  end
end
scenario({id = "note_text", kind = "text", title = "Test", state = "live",
  text = "Keep <b>https://example.com/a</b> & markup\nhttp://example.org/b?x=1&y=2."},
  {"https://example.com/a", "http://example.org/b?x=1&y=2"})
scenario({id = "note_list", kind = "checklist", title = "Test", state = "live", items = {
  {id = "item_a", position = 0, revision = "1", text = "https://example.com/a", checked = false},
  {id = "item_b", position = 1, revision = "2", text = "https://example.com/b", checked = true},
  {id = "item_c", position = 2, revision = "3", text = "Mixed https://example.com/c and text", checked = false},
}}, {"https://example.com/a", "https://example.com/b", "https://example.com/c"})
print("Actual Nodus panel: text/active/completed links open independently; checkboxes still work")
'''

with tempfile.TemporaryDirectory(prefix="nodus-link-panel-") as directory:
    path = Path(directory) / "test.luau"
    path.write_text(harness)
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(path)], cwd=ROOT, check=True)
