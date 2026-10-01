#!/usr/bin/env python3
"""Run copied Nodus contract fixtures and native URL-action tests with Lua 5.3+."""

import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixtures = json.loads((ROOT / "tools/fixtures/nodus-client-link-fixtures.json").read_text())


def literal(text):
    # Byte escapes preserve all Unicode/control bytes without Lua long-string
    # newline normalization or interpreting fixture content as source code.
    return '"' + ''.join(f'\\{byte:03d}' for byte in text.encode('utf-8')) + '"'


cases = []
for fixture in fixtures:
    expected = "{" + ",".join(literal(link) for link in fixture["links"]) + "}"
    cases.append(f'check({literal(fixture["name"])}, {literal(fixture["text"])}, {expected})')

harness = r'''
local Links = assert(loadfile("nodus/lib/links.luau"))()
local fixtureCount = 0
local function check(name, text, expected)
  local chunks, urls = {}, {}
  for _, segment in ipairs(Links.segments(text)) do
    table.insert(chunks, segment.text)
    if segment.href then
      assert(segment.text == segment.href, name .. ": changed label")
      assert(Links.isSafeHttpUrl(segment.href), name .. ": unsafe destination")
      table.insert(urls, segment.href)
    end
  end
  assert(table.concat(chunks) == text, name .. ": text changed")
  assert(#urls == #expected, name .. ": wrong match count " .. tostring(#urls))
  for i, url in ipairs(urls) do assert(url == expected[i], name .. ": wrong destination") end
  fixtureCount = fixtureCount + 1
end
''' + '\n'.join(cases) + r'''
-- Client-specific edge cases and unsafe activation inputs.
check("empty", "", {})
check("invalid-utf8", "https://example.com/" .. string.char(255), {})
check("nbsp-boundary", "a" .. utf8.char(0xa0) .. "https://example.com", {"https://example.com"})
check("trailing-extra-closers", "https://example.com/(a)]}", {"https://example.com/(a)"})
for _, c in ipairs({0x061c, 0x200e, 0x200f, 0x202a, 0x202e, 0x2066, 0x2069}) do
  check("bidi", "https://example.com/" .. utf8.char(c) .. "hidden", {})
end

local calls, errors, events = {}, 0, {}
local available, launched = true, true
local function node(kind)
  return function(props, children) return {kind = kind, props = props, children = children or {}} end
end
local ui = {row = node("row"), column = node("column"), label = node("label"), glyph = node("glyph")}
local env = setmetatable({
  require = function(path) assert(path == "./links.luau"); return Links end,
  ui = ui,
  noctalia = {
    commandExists = function(name) assert(name == "xdg-open"); return available end,
    runAsync = function(argv)
      assert(type(argv) == "table" and #argv == 2 and argv[1] == "xdg-open")
      table.insert(calls, argv)
      return launched
    end,
    notifyError = function(title, message) assert(title == "Nodus"); errors = errors + 1 end,
    -- No state/HTTP/write APIs: opening a link cannot mutate notes or fetch a preview.
  },
}, {__index = _G})
local View = assert(loadfile("nodus/lib/link_view.luau", "t", env))()
for _, checked in ipairs({false, true}) do
  local url = "https://www.biltema.no/a?x=1&y=2"
  local content = ui.label({text = url, opacity = checked and 0.65 or 1})
  local row = View.render(url, content)
  assert(row.kind == "row" and row.children[1] == content)
  assert(row.props.onClick ~= nil)
  assert(#calls == #events, "render opened a URL")
  row.props.onClick()
  table.insert(events, url)
  assert(calls[#calls][2] == url)

  local text = "<img src=x onerror=bad()> " .. url .. "\nthen http://example.org/a_(b)."
  content = ui.label({text = text, opacity = checked and 0.65 or 1})
  local mixed = View.render(text, content)
  assert(mixed.kind == "column" and #mixed.children == 3)
  assert(mixed.children[1] == content and content.props.text == text)
  assert(mixed.props.onClick == nil and content.props.onClick == nil)
  for i, target in ipairs({url, "http://example.org/a_(b)"}) do
    local action = mixed.children[i + 1]
    assert(action.kind == "row" and action.children[2].props.text == target)
    action.props.onClick()
    table.insert(events, target)
    assert(calls[#calls][2] == target)
  end
  local plain = ui.label({text = "javascript:https://example.com"})
  assert(View.render(plain.props.text, plain) == plain)
end
local before = #calls
for _, bad in ipairs({"javascript:alert(1)", "file:///tmp/a", "data:text/html,x", "//example.com", "https://user@example.com",
  "https://example.com:0", "https://example.com:65536", "https://example.com\n", "https://example.com/" .. utf8.char(0x202e)}) do
  assert(not View.open(bad), "opener accepted " .. bad)
end
assert(not View.open(nil))
assert(#calls == before, "unsafe URL reached opener")
-- Shell metacharacters in a valid URL are one literal argv value, never a shell command.
local literalUrl = "https://example.com/$(touch)/a;cmd&x=1"
assert(View.open(literalUrl))
assert(calls[#calls][2] == literalUrl)
local unicodeUrl = "https://例子.测试/路径?q=blå&x=1"
assert(View.open(unicodeUrl))
assert(calls[#calls][2] == unicodeUrl)
available = false
assert(not View.open("https://example.com"))
available, launched = true, false
assert(not View.open("https://example.com"))
assert(errors == 2)
print("Nodus links: " .. tostring(fixtureCount) .. " fixtures plus native actions, safe opening and failure checks passed")
'''

with tempfile.TemporaryDirectory(prefix="nodus-links-") as directory:
    path = Path(directory) / "test.lua"
    path.write_text(harness)
    subprocess.run(["lua", str(path)], cwd=ROOT, check=True)
