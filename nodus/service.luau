--!nonstrict

local helper = noctalia.expandPath("~/.local/bin/nodus-noctalia")
local busy = false
local pending = nil
local notes = {}
local counts = { active = 0, archive = 0, trash = 0 }
local nextPage = false
local feedMore = false
local lastSync = 0
local tick = 0
local sequence = 0

local function connection(state, message)
  noctalia.state.set("connection", { state = state, message = message or "" })
end

local function run(args, done)
  local argv = { helper }
  for _, value in ipairs(args) do table.insert(argv, value) end
  local started = noctalia.runAsync(argv, function(result)
    if result.timedOut or result.stdoutTruncated then
      done(nil, "The helper did not return a complete response")
      return
    end
    local response = noctalia.json.decode(result.stdout or "")
    if type(response) ~= "table" or type(response.ok) ~= "boolean" then
      done(nil, "The helper returned an invalid response")
    elseif not response.ok or result.exitCode ~= 0 then
      done(nil, tostring(response.message or "Helper unavailable"))
    else
      done(response, nil)
    end
  end, 60000)
  if not started then done(nil, "Install the Nodus helper, then refresh") end
end

local dispatch
local function finish()
  busy = false
  if pending ~= nil then
    local command = pending
    pending = nil
    dispatch(command)
  end
end

local function sync(offset)
  busy = true
  connection("loading")
  run({ "sync", tostring(offset) }, function(response, err)
    if response == nil then
      connection(if string.find(err or "", "Pair this device", 1, true) then "unpaired" else "error", err)
    else
      if offset == 0 then notes = {} end
      for _, item in ipairs(response.notes or {}) do table.insert(notes, item) end
      nextPage = response.next == true
      feedMore = response.more == true
      if type(response.counts) == "table" then counts = response.counts end
      noctalia.state.set("notes", { items = notes, next = nextPage, counts = counts })
      connection(response.state, if response.state == "offline" then "Showing saved notes; Nodus is unreachable" else "")
      if offset == 0 then lastSync = if response.state == "rate_limited" then tick + 30 else tick end
    end
    finish()
  end)
end

local function detail(id, fresh)
  busy = true
  noctalia.state.set("detailError", "")
  local args = { "detail", id }
  if fresh then table.insert(args, "fresh") end
  run(args, function(response, err)
    if response ~= nil and type(response.path) == "string" and string.sub(response.path, -12) == "/detail.json" then
      local raw = noctalia.readFile(response.path)
      local value = if type(raw) == "string" then noctalia.json.decode(raw) else nil
      if type(value) == "table" and value.id == id then
        noctalia.state.set("selected", value)
      else
        noctalia.state.set("detailError", "Could not read the cached note")
      end
    else
      noctalia.state.set("detailError", err or "Could not open note")
    end
    finish()
  end)
end

local function afterWrite(sequenceValue, response, err, refreshNoteID)
  noctalia.state.set("capture", {
    sequence = sequenceValue,
    state = if response ~= nil then "saved" else "error",
    message = err or "",
  })
  if response ~= nil then
    lastSync = tick - 30
    local updatedNoteID = refreshNoteID or response.noteId
    if type(updatedNoteID) == "string" and pending == nil then
      pending = { action = "open", id = updatedNoteID, fresh = true }
    end
  end
  finish()
end

local function create(command)
  busy = true
  local current = command.sequence
  noctalia.state.set("capture", { sequence = current, state = "sending" })
  run({ "draft" }, function(response, err)
    if response == nil then afterWrite(current, nil, err); return end
    local draft = { kind = command.kind, title = command.title, text = command.text }
    if command.kind == "checklist" and #command.items > 0 then draft.items = command.items end
    local data = noctalia.json.encode(draft)
    if type(response.path) ~= "string" or type(data) ~= "string" or not noctalia.writeFile(response.path, data) then
      afterWrite(current, nil, "Could not save the private draft")
      return
    end
    run({ "create", response.path }, function(saved, writeError)
      afterWrite(current, saved, writeError)
    end)
  end)
end

local function toggle(command)
  busy = true
  noctalia.state.set("capture", { sequence = command.sequence, state = "sending" })
  run({ "checked", command.noteId, command.itemId, command.revision, if command.checked then "true" else "false" }, function(saved, err)
    afterWrite(command.sequence, saved, err, command.noteId)
  end)
end

dispatch = function(command)
  if busy then pending = command; return end
  if command.action == "refresh" then if lastSync <= tick then sync(0) end
  elseif command.action == "more" then if nextPage and lastSync <= tick then sync(#notes) end
  elseif command.action == "open" and type(command.id) == "string" then detail(command.id, command.fresh == true)
  elseif command.action == "create" and type(command.title) == "string" and type(command.text) == "string"
    and (command.kind == "text" or (command.kind == "checklist" and type(command.items) == "table")) then create(command)
  elseif command.action == "checked" and type(command.noteId) == "string" and type(command.itemId) == "string"
    and type(command.revision) == "string" and type(command.checked) == "boolean" then toggle(command)
  elseif command.action == "retry" then
    busy = true
    run({ "retry" }, function(response, err) afterWrite(command.sequence, response, err) end)
  end
end

noctalia.state.watch("command", function(command)
  if type(command) ~= "table" or type(command.sequence) ~= "number" or command.sequence == sequence then return end
  sequence = command.sequence
  dispatch(command)
end)

function update()
  noctalia.setUpdateInterval(1000)
  tick += 1
  if not busy and (tick == 1 or (feedMore and tick >= lastSync) or tick - lastSync >= 30) then
    sync(0)
    lastSync = tick
  end
end
