#!/usr/bin/env python3
"""Exercise Markdown task parsing and source-safe marker replacement."""

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TESTS = r'''
local Task = dofile('memos/lib/task.luau')

local function taskAt(tasks, index, checked, text)
  local task = tasks[index]
  assert(task ~= nil)
  assert(task.checked == checked)
  assert(task.text == text)
  return task
end

local source = '- [ ] first\n  1. [X] nested\n4. [x] ordered\n- ordinary\n'
local tasks = Task.find(source)
assert(#tasks == 3)
taskAt(tasks, 1, false, 'first')
taskAt(tasks, 2, true, 'nested')
taskAt(tasks, 3, true, 'ordered')

local nested = '- parent\n    - [ ] child\n'
local nestedTasks = Task.find(nested)
assert(#nestedTasks == 1 and nestedTasks[1].indent == 4)

for _, falsePositive in ipairs({
  '[ ] prose',
  '- [ ]missing-space',
  '    - [ ] indented code',
  '```\n- [ ] fenced\n```',
  '- ```\n  - [ ] nested fenced\n  ```',
  '- parent\n\n    ```\n    - [ ] nested fenced\n    ```',
  '<div>\n- [ ] html block\n</div>',
  '<script>\n- [ ] raw html\n</script>',
  '<style>\n- [ ] raw html\n</style>',
  '<pre>\n- [ ] raw html\n</pre>',
  '</div>\n- [ ] closing html block',
  '<!DOCTYPE html\n- [ ] declaration body\n>',
  '<custom-element>\n- [ ] custom html block',
  '    plain code',
}) do
  assert(#Task.find(falsePositive) == 0)
end

local quoted = Task.find('> - [ ] quoted\n')
assert(#quoted == 1 and quoted[1].text == 'quoted' and quoted[1].quoteDepth == 1)
assert(Task.replaceMarker('> - [ ] quoted\n', quoted[1], true) == '> - [x] quoted\n')

assert(#Task.find('<div>\n\n- [ ] after html\n') == 1)
assert(#Task.find('> ```\n> code\n- [ ] after quote\n') == 1)
assert(#Task.find('- ```\n  code\n- [ ] after item\n') == 1)

local mixed = Task.find('- [ ] parent\n    - [ ] child\n    - ordinary\n')
assert(#mixed == 2)
local renderedFragment, fragmentIndent = Task.renderFragment('    - ordinary\n')
assert(renderedFragment == '- ordinary\n' and fragmentIndent == 4)
local fragments = Task.renderFragments('    - ordinary\n- top\n')
assert(#fragments == 2)
assert(fragments[1].text == '- ordinary\n' and fragments[1].indent == 4)
assert(fragments[2].text == '- top\n' and fragments[2].indent == 0)

local withChild = Task.find('- [ ] parent\n    - child\n')
assert(#withChild == 1 and withChild[1].continuationText == '- child')

local emptyAndCase = '* [ ]\n+ [X] UPPER\n'
local caseTasks = Task.find(emptyAndCase)
assert(#caseTasks == 2)
assert(caseTasks[1].text == '' and not caseTasks[1].checked)
assert(caseTasks[2].checked)
local unchanged = assert(Task.replaceMarker(emptyAndCase, caseTasks[2], true))
assert(unchanged == emptyAndCase)

local unicodeCrLf = '😀 intro\r\n- [ ] café 😀\r\n- [ ] café 😀\r\n'
local unicodeTasks = Task.find(unicodeCrLf)
assert(#unicodeTasks == 2)
local toggled = assert(Task.replaceMarker(unicodeCrLf, unicodeTasks[2], true))
assert(toggled == '😀 intro\r\n- [ ] café 😀\r\n- [x] café 😀\r\n')
assert(#toggled == #unicodeCrLf)

local upper = '- [X] done\n'
local upperTask = Task.find(upper)[1]
assert(Task.replaceMarker(upper, upperTask, true) == upper)
assert(Task.replaceMarker(upper, upperTask, false) == '- [ ] done\n')

local wrongState = {}
for key, value in pairs(upperTask) do wrongState[key] = value end
wrongState.checked = false
assert(Task.replaceMarker(upper, wrongState, true) == nil)
local shifted = {}
for key, value in pairs(upperTask) do shifted[key] = value end
shifted.markerStart = shifted.markerStart + 1
shifted.markerEnd = shifted.markerEnd + 1
assert(Task.replaceMarker(upper, shifted, false) == nil)
local invalidRange = {}
for key, value in pairs(upperTask) do invalidRange[key] = value end
invalidRange.markerEnd = invalidRange.markerStart + 2
assert(Task.replaceMarker(upper, invalidRange, false) == nil)

local relabeled = '- [ ] changed label\n'
local originalRef = Task.find('- [ ] old label\n')[1]
assert(Task.replaceMarker(relabeled, originalRef, true) == '- [x] changed label\n')

print('Markdown task tests passed.')
'''

subprocess.run(["lua", "-"], input=TESTS, text=True, cwd=ROOT, check=True)
