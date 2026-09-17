--!nonstrict

local Client = require("./lib/client.luau")
local Reminder = require("./lib/reminder.luau")
local Space = require("./lib/space.luau")
local Task = require("./lib/task.luau")
local spaces = {}
local selectedSpace = ""
local scopeRevision = 0
local spacesGeneration = 0
local spacesReady = false
local editableMemos = {}

local RECONNECT_DELAYS = { 1, 2, 4, 8, 16, 30, 60 }
local client = nil
local currentUserName = ""
local streamHandle = nil
local tick = 0
local reconnectAt = nil
local reconnectAttempt = 0
local sseState = "disconnected"
local fetchInFlight = false
local fetchAgain = false
local validationInFlight = false
local connected = false
local stopping = false
local reminders = {}
local reminderFetchInFlight = false
local reminderFetchAgain = false
local deliveredReminders = {}
local deliveriesPath = nil
local REMINDER_CATCH_UP_SECONDS = 24 * 60 * 60
local DELIVERY_RETENTION_SECONDS = 2 * REMINDER_CATCH_UP_SECONDS

local function shellQuote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function publishConnection(state, sse, httpStatus)
  if sse ~= nil then
    sseState = sse
  end
  noctalia.state.set("connection", {
    state = state,
    sse = sseState,
    httpStatus = httpStatus or 0,
  })
end

local function publishCapture(state, sequence, errorCode)
  noctalia.state.set("capture", {
    state = state,
    sequence = sequence or 0,
    error = errorCode or "",
  })
end

local function loadDeliveredReminders()
  local directory = noctalia.pluginDataDir()
  if type(directory) ~= "string" or directory == "" then
    return
  end
  deliveriesPath = directory .. "/reminder-deliveries.json"
  noctalia.runAsync("chmod 700 " .. shellQuote(directory), function(_result) end, 5000)
  local raw = noctalia.readFile(deliveriesPath)
  if type(raw) ~= "string" or raw == "" then
    return
  end
  local payload = noctalia.json.decode(raw)
  if type(payload) ~= "table" then
    return
  end
  for key, deliveredAt in pairs(payload) do
    if type(key) == "string" and type(deliveredAt) == "number" then
      deliveredReminders[key] = deliveredAt
    end
  end
end

local function persistDeliveredReminders()
  if deliveriesPath == nil then
    return
  end
  local body = noctalia.json.encode(deliveredReminders)
  if body ~= nil and noctalia.writeFile(deliveriesPath, body .. "\n") then
    noctalia.runAsync("chmod 600 " .. shellQuote(deliveriesPath), function(_result) end, 5000)
  end
end

local function checkReminders()
  local now = os.time()
  local changed = false
  for key, deliveredAt in pairs(deliveredReminders) do
    if now - deliveredAt > DELIVERY_RETENTION_SECONDS then
      deliveredReminders[key] = nil
      changed = true
    end
  end

  for _, memo in ipairs(reminders) do
    local due = Reminder.fromRfc3339(memo.reminderTime)
    local key = memo.name .. "|" .. memo.reminderTime
    if due ~= nil
      and due <= now
      and due >= now - REMINDER_CATCH_UP_SECONDS
      and deliveredReminders[key] == nil
    then
      deliveredReminders[key] = now
      changed = true
      local body = memo.snippet
      if type(body) ~= "string" or noctalia.string.trim(body) == "" then
        body = noctalia.tr("reminders.empty_notification")
      end
      noctalia.notify(noctalia.tr("reminders.notification_title"), body)
    end
  end

  if changed then
    persistDeliveredReminders()
  end
end

local function stopStream()
  if streamHandle ~= nil then
    streamHandle.stop()
    streamHandle = nil
  end
end

local function setConnectionFailure(code, httpStatus)
  connected = false
  currentUserName = ""
  reconnectAt = nil
  reminders = {}
  reminderFetchInFlight = false
  reminderFetchAgain = false
  stopStream()
  publishConnection(code, "disconnected", httpStatus)
end

local function scheduleReconnect()
  reconnectAttempt += 1
  local index = math.min(reconnectAttempt, #RECONNECT_DELAYS)
  reconnectAt = tick + RECONNECT_DELAYS[index]
  publishConnection("connected", "reconnecting")
end

local fetchMemos
local fetchReminders
local startStream
local fetchSpaces

local function publishSpaces(state)
  noctalia.state.set("spaces", { items = spaces, selected = selectedSpace, revision = scopeRevision, state = state })
end

local function invalidateScope()
  scopeRevision += 1
  fetchInFlight = false
  fetchAgain = false
  editableMemos = {}
  noctalia.state.set("memos", {})
end

fetchMemos = function()
  if selectedSpace ~= "" and (not spacesReady or not Space.contains(spaces, selectedSpace)) then return end
  if not connected or client == nil or currentUserName == "" then
    return
  end
  if fetchInFlight then
    fetchAgain = true
    return
  end

  fetchInFlight = true
  fetchAgain = false
  local requestClient = client
  local requestRevision = scopeRevision
  local filter = Space.filter(currentUserName, selectedSpace)
  local path = "/api/v1/memos?pageSize=20&state=NORMAL&orderBy="
    .. noctalia.string.urlEncode("pinned desc, create_time desc")
    .. "&filter="
    .. noctalia.string.urlEncode(filter)

  local accepted = Client.request(client, "GET", path, nil, function(response)
    if client ~= requestClient or scopeRevision ~= requestRevision or not connected then return end
    fetchInFlight = false
    local statusError = Client.statusError(response)
    if statusError ~= nil then
      if statusError == "unauthorized" or statusError == "forbidden" then
        setConnectionFailure(statusError, response.status)
      else
        publishConnection(statusError, sseState, response.status)
      end
      return
    end

    local payload, decodeError = Client.decodeObject(response.body)
    if payload == nil or type(payload.memos) ~= "table" then
      publishConnection(decodeError or "invalid_json", sseState, response.status)
      return
    end

    local memos = {}
    editableMemos = {}
    for _, memo in ipairs(payload.memos) do
      if type(memo) == "table" then
        local canEdit = memo.creator == currentUserName
        local memoName = ""
        local content = ""
        if type(memo.name) == "string" then memoName = memo.name end
        if type(memo.content) == "string" then content = memo.content end
        if canEdit and memoName ~= "" then editableMemos[memoName] = content end
        table.insert(memos, {
          canEdit = canEdit,
          name = memoName,
          content = content,
          createTime = if type(memo.createTime) == "string" then memo.createTime else "",
          visibility = if type(memo.visibility) == "string" then memo.visibility else "",
          pinned = memo.pinned == true,
          reminderTime = if type(memo.reminderTime) == "string" then memo.reminderTime else "",
        })
      end
    end
    noctalia.state.set("memos", memos)
    publishConnection("connected", sseState)

    if fetchAgain then
      fetchMemos()
    end
  end)

  if not accepted then
    fetchInFlight = false
    publishConnection("request_rejected", "disconnected")
  end
end

fetchSpaces = function()
  if not connected or client == nil then return end
  spacesGeneration += 1
  local generation = spacesGeneration
  local requestClient = client
  local collected = {}
  spacesReady = false
  publishSpaces("loading")
  local fetchPage
  local function fail()
    spacesReady = false
    invalidateScope()
    publishSpaces("error")
  end
  fetchPage = function(token)
    local path = "/api/v1/spaces?pageSize=1000"
    if token ~= "" then path ..= "&pageToken=" .. noctalia.string.urlEncode(token) end
    local accepted = Client.request(requestClient, "GET", path, nil, function(response)
      if client ~= requestClient or generation ~= spacesGeneration or not connected then return end
      if Client.statusError(response) ~= nil then fail(); return end
      local payload = Client.decodeObject(response.body)
      if payload == nil or type(payload.spaces) ~= "table" then fail(); return end
      for _, space in ipairs(payload.spaces) do
        if Space.accessible(space) then table.insert(collected, space) end
      end
      if type(payload.nextPageToken) == "string" and payload.nextPageToken ~= "" then
        fetchPage(payload.nextPageToken)
        return
      end
      spaces = collected
      spacesReady = true
      -- Never silently redirect a draft when membership disappears.
      if not Space.contains(spaces, selectedSpace) then
        invalidateScope()
        publishSpaces("unavailable")
        return
      end
      publishSpaces("ready")
      fetchMemos()
    end)
    if not accepted then fail() end
  end
  fetchPage("")
end

fetchReminders = function()
  if not connected or client == nil or currentUserName == "" then
    return
  end
  if reminderFetchInFlight then
    reminderFetchAgain = true
    return
  end

  reminderFetchInFlight = true
  reminderFetchAgain = false
  local requestClient = client
  local collected = {}
  local filter = `creator == "{currentUserName}"`
  local fetchPage

  local function finish(success)
    reminderFetchInFlight = false
    if success then
      reminders = collected
    end
    if reminderFetchAgain and connected and client == requestClient then
      fetchReminders()
    end
  end

  fetchPage = function(pageToken)
    local path = "/api/v1/memos?pageSize=1000&state=NORMAL&filter=" .. noctalia.string.urlEncode(filter)
    if pageToken ~= "" then
      path ..= "&pageToken=" .. noctalia.string.urlEncode(pageToken)
    end

    local accepted = Client.request(requestClient, "GET", path, nil, function(response)
      if client ~= requestClient then
        return
      end
      local statusError = Client.statusError(response)
      if statusError ~= nil then
        reminderFetchInFlight = false
        if statusError == "unauthorized" or statusError == "forbidden" then
          setConnectionFailure(statusError, response.status)
        else
          publishConnection(statusError, sseState, response.status)
        end
        return
      end

      local payload, decodeError = Client.decodeObject(response.body)
      if payload == nil or type(payload.memos) ~= "table" then
        publishConnection(decodeError or "invalid_json", sseState, response.status)
        finish(false)
        return
      end

      for _, memo in ipairs(payload.memos) do
        if type(memo) == "table"
          and type(memo.name) == "string"
          and memo.name ~= ""
          and type(memo.reminderTime) == "string"
          and memo.reminderTime ~= ""
        then
          table.insert(collected, {
            name = memo.name,
            reminderTime = memo.reminderTime,
            snippet = if type(memo.snippet) == "string" then memo.snippet else "",
          })
        end
      end

      local nextPageToken = if type(payload.nextPageToken) == "string" then payload.nextPageToken else ""
      if nextPageToken ~= "" then
        fetchPage(nextPageToken)
      else
        finish(true)
      end
    end)

    if not accepted then
      publishConnection("request_rejected", sseState)
      finish(false)
    end
  end

  fetchPage("")
end

startStream = function()
  if not connected or client == nil or streamHandle ~= nil then
    return
  end

  reconnectAt = nil
  publishConnection("connected", "connecting")
  local handle = Client.stream(client, "/api/v1/sse", function(line)
    if line == ": connected" or line == ": heartbeat" then
      reconnectAttempt = 0
      publishConnection("connected", "connected")
      return
    end
    if string.sub(line, 1, 5) ~= "data:" then
      return
    end

    local payload = noctalia.string.trim(string.sub(line, 6))
    local event = noctalia.json.decode(payload)
    if type(event) == "table" and event.type == "space.changed" then
      fetchSpaces()
    end
    if type(event) == "table" and event.type == "memo.changed" then
      fetchMemos()
      fetchReminders()
    end
  end, function(result)
    streamHandle = nil
    if stopping then
      return
    end
    if type(result) == "table" and (result.status == 401 or result.status == 403) then
      setConnectionFailure(if result.status == 401 then "unauthorized" else "forbidden", result.status)
      return
    end
    scheduleReconnect()
  end)

  if handle == nil then
    scheduleReconnect()
    return
  end
  streamHandle = handle
end

local function validateConnection()
  if validationInFlight then
    return
  end

  stopStream()
  invalidateScope()
  spacesGeneration += 1
  spaces = {}
  -- Keep the destination across reconnects; never redirect an existing draft.
  spacesReady = false
  publishSpaces("loading")
  client = nil
  connected = false
  currentUserName = ""
  reconnectAt = nil
  reconnectAttempt = 0
  fetchInFlight = false
  fetchAgain = false
  reminderFetchInFlight = false
  reminderFetchAgain = false
  reminders = {}
  noctalia.state.set("memos", {})

  local configError
  client, configError = Client.load()
  if client == nil then
    publishConnection(configError or "unconfigured", "disconnected")
    return
  end

  validationInFlight = true
  publishConnection("connecting", "disconnected")
  local accepted = Client.request(client, "GET", "/api/v1/auth/me", nil, function(response)
    validationInFlight = false
    local statusError = Client.statusError(response)
    if statusError ~= nil then
      setConnectionFailure(statusError, response.status)
      return
    end

    local payload, decodeError = Client.decodeObject(response.body)
    if payload == nil
      or type(payload.user) ~= "table"
      or type(payload.user.name) ~= "string"
      or string.match(payload.user.name, "^users/[^/]+$") == nil
    then
      setConnectionFailure(decodeError or "invalid_json", response.status)
      return
    end

    currentUserName = payload.user.name
    connected = true
    publishConnection("connected", "connecting")
    fetchMemos()
    fetchSpaces()
    fetchReminders()
    startStream()
  end)

  if not accepted then
    validationInFlight = false
    setConnectionFailure("request_rejected")
  end
end

local function createMemo(sequence, content, reminderTime, destination, revision)
  if not connected or client == nil then
    publishCapture("error", sequence, "not_connected")
    return
  end
  if type(content) ~= "string" or noctalia.string.trim(content) == "" then
    publishCapture("error", sequence, "empty_memo")
    return
  end

  if destination ~= selectedSpace or revision ~= scopeRevision
    or not Space.contains(spaces, destination) or (destination ~= "" and not spacesReady) then
    publishCapture("error", sequence, "scope_changed")
    return
  end

  local memo = {
    content = content,
    state = "NORMAL",
    visibility = "PRIVATE",
  }
  Space.destination(memo, destination)
  if type(reminderTime) == "string" and Reminder.fromRfc3339(reminderTime) ~= nil then
    memo.reminderTime = reminderTime
  end
  local body = noctalia.json.encode(memo)
  if body == nil then
    publishCapture("error", sequence, "encode_failed")
    return
  end

  local requestClient = client
  publishCapture("sending", sequence)
  local accepted = Client.request(requestClient, "POST", "/api/v1/memos", body, function(response)
    if client ~= requestClient then
      publishCapture("error", sequence, "not_connected")
      return
    end
    local statusError = Client.statusError(response)
    if statusError ~= nil then
      publishCapture("error", sequence, statusError)
      if statusError == "unauthorized" or statusError == "forbidden" then
        setConnectionFailure(statusError, response.status)
      end
      return
    end

    local memo, decodeError = Client.decodeObject(response.body)
    if memo == nil or type(memo.name) ~= "string" or memo.name == "" then
      publishCapture("error", sequence, decodeError or "invalid_json")
      return
    end

    publishCapture("success", sequence)
    fetchMemos()
    fetchReminders()
  end)

  if not accepted then
    publishCapture("error", sequence, "request_rejected")
  end
end

local mutationInFlight = false

local function mutateMemo(command)
  if mutationInFlight then
    return
  end
  local sequence = tonumber(command.sequence) or 0
  local function publish(state, errorCode)
    noctalia.state.set("mutation", { state = state, sequence = sequence, error = errorCode or "" })
  end
  if not connected or client == nil then
    publish("error", "not_connected")
    return
  end
  if type(command.name) ~= "string" or string.match(command.name, "^memos/[%w_-]+$") == nil then
    publish("error", "invalid_memo")
    return
  end
  if not editableMemos[command.name] then
    publish("error", "forbidden")
    return
  end
  local path = "/api/v1/" .. command.name
  if command.action == "toggle_task" then
    if type(command.baseContent) ~= "string" or editableMemos[command.name] ~= command.baseContent then
      publish("error", "conflict")
      return
    end
    local content, taskError = Task.replaceMarker(command.baseContent, {
      markerStart = command.markerStart,
      markerEnd = command.markerEnd,
      line = command.line,
      checked = command.previousChecked,
    }, command.checked)
    if content == nil then
      publish("error", taskError or "invalid_task")
      return
    end
    if content == command.baseContent then
      publish("success")
      return
    end
    local body = noctalia.json.encode({ content = content })
    if body == nil then
      publish("error", "encode_failed")
      return
    end

    local requestClient = client
    local function fail(errorCode, response)
      mutationInFlight = false
      publish("error", errorCode)
      if response ~= nil and (errorCode == "unauthorized" or errorCode == "forbidden") then
        setConnectionFailure(errorCode, response.status)
      end
    end
    local function succeed()
      mutationInFlight = false
      publish("success")
      fetchMemos()
      fetchReminders()
    end
    local function verifyRemote()
      local verifyAccepted = Client.request(requestClient, "GET", path, nil, function(verifyResponse)
        if client ~= requestClient then fail("not_connected"); return end
        local verifyError = Client.statusError(verifyResponse)
        if verifyError ~= nil then fail(verifyError, verifyResponse); return end
        local remote = Client.decodeObject(verifyResponse.body)
        if remote == nil or remote.content ~= content then fail("conflict"); return end
        succeed()
      end)
      if not verifyAccepted then fail("request_rejected") end
    end

    mutationInFlight = true
    publish("sending")
    local readAccepted = Client.request(requestClient, "GET", path, nil, function(readResponse)
      if client ~= requestClient then fail("not_connected"); return end
      local readError = Client.statusError(readResponse)
      if readError ~= nil then fail(readError, readResponse); return end
      local remote = Client.decodeObject(readResponse.body)
      if remote == nil or remote.content ~= command.baseContent or remote.state ~= "NORMAL" then
        fail("conflict")
        return
      end
      if remote.creator ~= currentUserName then fail("forbidden"); return end

      local patchAccepted = Client.request(
        requestClient,
        "PATCH",
        path .. "?updateMask=content,update_time",
        body,
        function(patchResponse)
          if client ~= requestClient then fail("not_connected"); return end
          local patchError = Client.statusError(patchResponse)
          if patchError ~= nil then fail(patchError, patchResponse); return end
          local patched = Client.decodeObject(patchResponse.body)
          if patched ~= nil and type(patched.content) == "string" then
            if patched.content ~= content then fail("conflict") else succeed() end
            return
          end
          verifyRemote()
        end
      )
      if not patchAccepted then fail("request_rejected") end
    end)
    if not readAccepted then fail("request_rejected") end
    return
  end

  local fields = { name = command.name }
  local mask
  if command.action == "update" then
    if type(command.content) ~= "string" or noctalia.string.trim(command.content) == "" then
      publish("error", "empty_memo")
      return
    end
    mask = "content"
    fields.content = command.content
  elseif command.action == "pin" and type(command.pinned) == "boolean" then
    mask = "pinned"
    fields.pinned = command.pinned
  elseif command.action == "archive" then
    mask = "state"
    fields.state = "ARCHIVED"
  else
    publish("error", "invalid_memo")
    return
  end
  path = path .. "?updateMask=" .. mask
  local body = noctalia.json.encode(fields)
  if body == nil then
    publish("error", "encode_failed")
    return
  end
  local requestClient = client
  mutationInFlight = true
  publish("sending")
  local accepted = Client.request(requestClient, "PATCH", path, body, function(response)
    mutationInFlight = false
    if client ~= requestClient then
      publish("error", "not_connected")
      return
    end
    local errorCode = Client.statusError(response)
    if errorCode ~= nil then
      publish("error", errorCode)
      if errorCode == "unauthorized" or errorCode == "forbidden" then
        setConnectionFailure(errorCode, response.status)
      end
      return
    end
    publish("success")
    fetchMemos()
    fetchReminders()
  end)
  if not accepted then
    mutationInFlight = false
    publish("error", "request_rejected")
  end
end

local function handleCommand(command)
  if type(command) ~= "table" or type(command.action) ~= "string" then
    return
  end
  if command.action == "refresh" then
    if connected then
      fetchMemos()
      fetchSpaces()
    else
      validateConnection()
    end
  elseif command.action == "select_space" then
    if connected and type(command.space) == "string" and Space.contains(spaces, command.space)
      and (command.space == "" or spacesReady) then
      selectedSpace = command.space
      invalidateScope()
      publishSpaces("ready")
      fetchMemos()
    end
  elseif command.action == "credentials_changed" then
    validateConnection()
  elseif command.action == "update" or command.action == "toggle_task"
    or command.action == "pin" or command.action == "archive"
  then
    noctalia.state.set("command", { action = "ack", sequence = command.sequence })
    mutateMemo(command)
  elseif command.action == "create" then
    local sequence = tonumber(command.sequence) or 0
    local content = command.content
    local reminderTime = command.reminderTime
    noctalia.state.set("command", { action = "ack", sequence = sequence })
    createMemo(sequence, content, reminderTime, command.space, command.scopeRevision)
  end
end

noctalia.state.watch("command", handleCommand)
noctalia.setUpdateInterval(1000)
publishCapture("idle", 0)
loadDeliveredReminders()
validateConnection()

function update()
  tick += 1
  if connected and streamHandle == nil and reconnectAt ~= nil and tick >= reconnectAt then
    startStream()
  end
  if connected then
    checkReminders()
  end
end

function onIpc(event, _payload)
  if event == "refresh" or event == "validate" then
    validateConnection()
  end
end

function onExit(_signal, _reason)
  stopping = true
  stopStream()
end
