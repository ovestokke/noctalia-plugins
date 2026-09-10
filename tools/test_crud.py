#!/usr/bin/env python3
"""Exercise the service mutation handler with a mocked Noctalia HTTP client.

Requires Lua; the extracted handler is also valid standard Lua.
No requests are sent to a real Memos instance.
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "memos/service.luau").read_text()
handler = source.split("local mutationInFlight = false", 1)[1].split("local function handleCommand", 1)[0]
handler = 'local mutationInFlight = false\n' + handler
preamble = r'''
local connected, client = true, {}
local state, request, callback, encoded
local requests, refreshes = 0, 0
local accept, encode = true, true
local noctalia = {
  state = {set = function(_, value) state = value end},
  string = {trim = function(s) return s:match('^%s*(.-)%s*$') end},
  json = {encode = function(value) encoded = value; if encode then return 'body' end end},
}
local Client = {
  request = function(_, method, path, body, done)
    requests = requests + 1
    request = {method = method, path = path, body = body}
    callback = done
    return accept
  end,
  statusError = function(response)
    if not response.ok then return 'network_error' end
    if response.status == 403 then return 'forbidden' end
    if response.status >= 300 then return 'server_error' end
  end,
}
local function setConnectionFailure() connected = false end
local function fetchMemos() refreshes = refreshes + 1 end
local function fetchReminders() refreshes = refreshes + 1 end
'''
tests = r'''
local function update(content, name)
  mutateMemo({action = 'update', sequence = 7, name = name or 'memos/abc-123', content = content})
end
update('new text')
assert(state.state == 'sending' and state.sequence == 7)
assert(request.method == 'PATCH' and request.path == '/api/v1/memos/abc-123?updateMask=content')
assert(encoded.content == 'new text' and encoded.visibility == nil and encoded.reminderTime == nil)
update('duplicate')
assert(requests == 1)
callback({ok = true, status = 200})
assert(state.state == 'success' and refreshes == 2)
mutateMemo({action = 'archive', sequence = 8, name = 'memos/abc-123'})
assert(request.method == 'PATCH' and encoded.state == 'ARCHIVED' and encoded.content == nil)
assert(request.path == '/api/v1/memos/abc-123?updateMask=state')
callback({ok = true, status = 204})
assert(state.state == 'success' and refreshes == 4)
update('   ')
assert(state.error == 'empty_memo' and requests == 2)
update('text', 'memos/../users/1')
assert(state.error == 'invalid_memo' and requests == 2)
encode = false
update('text')
assert(state.error == 'encode_failed')
encode, accept = true, false
update('text')
assert(state.error == 'request_rejected')
accept = true
update('retry')
callback({ok = false})
assert(state.error == 'network_error' and refreshes == 4)
update('retry')
callback({ok = true, status = 403})
assert(state.error == 'forbidden' and not connected)
update('offline')
assert(state.error == 'not_connected')
connected = true
update('old connection')
client = {}
callback({ok = true, status = 200})
assert(state.error == 'not_connected' and refreshes == 4)
for _, pinned in ipairs({true, false}) do
  mutateMemo({action = 'pin', sequence = 9, name = 'memos/abc-123', pinned = pinned})
  assert(request.method == 'PATCH' and request.path == '/api/v1/memos/abc-123?updateMask=pinned')
  assert(encoded.pinned == pinned and encoded.state == nil and encoded.content == nil)
  callback({ok = true, status = 200})
  assert(state.state == 'success')
end
local before = requests
mutateMemo({action = 'pin', name = 'memos/abc-123'})
assert(state.error == 'invalid_memo' and requests == before)
mutateMemo({action = 'delete', name = 'memos/abc-123'})
assert(state.error == 'invalid_memo' and requests == before)
print('Memo action tests passed.')
'''
subprocess.run(['lua', '-'], input=preamble + handler + tests, text=True, check=True)
