#!/usr/bin/env python3
"""Run actual scope/list/create handlers under Lua with mocked native HTTP.

Only Luau compound assignments and simple inline conditionals are translated.
No credentials, network, or running Noctalia instance are used.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'memos/service.luau').read_text()
space = (ROOT / 'memos/lib/space.luau').read_text().replace('return Space', '')
handlers = source.split('local function publishSpaces', 1)[1].split('fetchReminders = function()', 1)[0]
handlers = 'local function publishSpaces' + handlers
handlers += 'local function createMemo' + source.split('local function createMemo', 1)[1].split('local mutationInFlight', 1)[0]
handlers = re.sub(r'(\w+) \+= ([^\n]+)', r'\1 = \1 + \2', handlers)
handlers = handlers.replace('path ..=', 'path = path ..')
handlers = re.sub(r'= if (.*?) then (.*?) else (.*?),\n', r'= choose(\1, \2, \3),\n', handlers)
preamble = r'''
local function choose(test, yes, no) if test then return yes else return no end end
local connected, client, currentUserName = true, {}, 'users/me'
local spaces, selectedSpace, scopeRevision = {}, '', 0
local spacesGeneration, spacesReady = 0, false
local fetchInFlight, fetchAgain, editableMemos = false, false, {}
local fetchMemos, fetchSpaces
local state, requests, encoded = {}, {}, nil
local noctalia = {
  state = {set = function(key, value) state[key] = value end},
  string = {urlEncode = function(s) return s end, trim = function(s) return s:match('^%s*(.-)%s*$') end},
  json = {encode = function(value)
    if type(value) == 'string' then return string.format('%q', value) end
    encoded = value; return 'body'
  end},
}
local Client = {
  request = function(c, method, path, body, callback)
    table.insert(requests, {client = c, method = method, path = path, body = body, done = callback})
    return true
  end,
  statusError = function(response) if response.status ~= 200 then return 'server_error' end end,
  decodeObject = function(body) return body end,
}
local Reminder = {fromRfc3339 = function(value) return value == 'valid' and 1 or nil end}
local function publishConnection(value) state.connection = value end
local function setConnectionFailure() connected = false end
local function publishCapture(value, sequence, err) state.capture = {state = value, sequence = sequence, error = err} end
local remindersFetched = 0
local function fetchReminders() remindersFetched = remindersFetched + 1 end
local function reply(request, body) request.done({status = 200, body = body}) end
'''
tests = r'''
assert(Space.filter('users/me', '') == 'creator == "users/me" && space == null')
assert(Space.filter('users/me', 'spaces/team') == 'space == "spaces/team"')
assert(Space.accessible({name = 'spaces/team', currentUserRole = 'USER'}))
assert(Space.accessible({name = 'spaces/team', currentUserRole = 'ADMIN'}))
assert(not Space.accessible({name = 'spaces/team', currentUserRole = 'ROLE_UNSPECIFIED'}))
assert(not Space.accessible({name = 'spaces/bad"', currentUserRole = 'USER'}))
fetchSpaces()
local first = requests[#requests]
assert(first.path == '/api/v1/spaces?pageSize=1000')
reply(first, {spaces = {{name = 'spaces/team', title = 'Team', currentUserRole = 'USER'}}, nextPageToken = 'next'})
assert(requests[#requests].path:find('&pageToken=next', 1, true))
reply(requests[#requests], {spaces = {{name = 'spaces/other', currentUserRole = 'ADMIN'}, {name = 'spaces/metadata'}}})
assert(#spaces == 2 and spacesReady and state.spaces.state == 'ready')
local personalRequest = requests[#requests]
assert(personalRequest.path:find('creator == "users/me" && space == null', 1, true))
selectedSpace = 'spaces/team'; invalidateScope(); publishSpaces('ready'); fetchMemos()
local teamRequest = requests[#requests]
assert(teamRequest.path:find('space == "spaces/team"', 1, true))
assert(not teamRequest.path:find('creator', 1, true))
reply(personalRequest, {memos = {{name = 'memos/stale', creator = 'users/me'}}})
assert(#state.memos == 0 and fetchInFlight)
reply(teamRequest, {memos = {{name = 'memos/own', creator = 'users/me'}, {name = 'memos/theirs', creator = 'users/other'}}})
assert(#state.memos == 2 and state.memos[1].canEdit and not state.memos[2].canEdit)
assert(editableMemos['memos/own'] and not editableMemos['memos/theirs'])
createMemo(1, 'hello', 'valid', selectedSpace, scopeRevision)
local creation = requests[#requests]
assert(creation.method == 'POST' and creation.path == '/api/v1/memos')
assert(encoded.visibility == 'SPACE' and encoded.space == 'spaces/team' and encoded.reminderTime == 'valid')
local before = #requests
createMemo(2, 'wrong scope', nil, '', scopeRevision - 1)
assert(#requests == before and state.capture.error == 'scope_changed')
selectedSpace = ''; invalidateScope()
reply(creation, {name = 'memos/new'})
assert(state.capture.state == 'success' and remindersFetched == 1)
assert(requests[#requests].path:find('space == null', 1, true))
createMemo(3, 'private', nil, '', scopeRevision)
assert(encoded.visibility == 'PRIVATE' and encoded.space == nil)
-- A disappeared membership must not silently send the draft to personal.
selectedSpace = 'spaces/team'; invalidateScope(); fetchSpaces()
reply(requests[#requests], {spaces = {}})
assert(selectedSpace == 'spaces/team' and state.spaces.state == 'unavailable' and #state.memos == 0)
before = #requests
createMemo(4, 'do not redirect', nil, selectedSpace, scopeRevision)
assert(#requests == before and state.capture.error == 'scope_changed')
-- An old account's list cannot replace the new account's state.
selectedSpace = ''; fetchSpaces(); local old = requests[#requests]
client = {}; fetchSpaces(); local current = requests[#requests]
reply(current, {spaces = {}})
reply(old, {spaces = {{name = 'spaces/old-account', currentUserRole = 'USER'}}})
assert(#spaces == 0)
fetchMemos(); local oldMemos = requests[#requests]; client = {}
reply(oldMemos, {memos = {{name = 'memos/old-account'}}})
assert(#state.memos == 0)
-- Same-account refreshes are generation guarded, including late failures.
fetchSpaces(); local superseded = requests[#requests]
fetchSpaces(); local latest = requests[#requests]
reply(latest, {spaces = {{name = 'spaces/new', currentUserRole = 'USER'}}})
superseded.done({status = 500})
assert(spacesReady and #spaces == 1 and state.spaces.state == 'ready')
selectedSpace = 'spaces/new'; invalidateScope(); fetchSpaces()
requests[#requests].done({status = 500})
assert(not spacesReady and state.spaces.state == 'error' and #state.memos == 0)
before = #requests
createMemo(5, 'failed discovery', nil, selectedSpace, scopeRevision)
assert(#requests == before and state.capture.error == 'scope_changed')
selectedSpace = ''; invalidateScope()
createMemo(6, 'old account', nil, '', scopeRevision)
local oldCreate = requests[#requests]; client = {}
reply(oldCreate, {name = 'memos/old-create'})
assert(state.capture.error == 'not_connected')
print('Spaces mock tests passed: filters, pagination, membership, ownership, payloads, stale lists and capture races.')
'''
subprocess.run(['lua', '-'], input=preamble + space + handlers + tests, text=True, check=True)
# Reminders deliberately retain their creator-only scan across all placements.
reminders = source.split('fetchReminders = function()', 1)[1].split('startStream = function()', 1)[0]
assert 'creator == ' in reminders and 'selectedSpace' not in reminders and 'Space.filter' not in reminders
print('Reminder scope independence checked.')
validation = source.split('local function validateConnection()', 1)[1].split('local function createMemo', 1)[0]
assert 'selectedSpace = ""' not in validation, 'Reconnect must not silently redirect a Space draft'
print('Reconnect preserves draft destination.')
