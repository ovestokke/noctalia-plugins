--!nonstrict

local Client = require("./lib/client.luau")
local Reminder = require("./lib/reminder.luau")

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

fetchMemos = function()
  if not connected or client == nil or currentUserName == "" then
    return
  end
  if fetchInFlight then
    fetchAgain = true
    return
  end

  fetchInFlight = true
  fetchAgain = false
  local filter = `creator == "{currentUserName}"`
  local path = "/api/v1/memos?pageSize=20&state=NORMAL&orderBy="
    .. noctalia.string.urlEncode("create_time desc")
    .. "&filter="
    .. noctalia.string.urlEncode(filter)

  local accepted = Client.request(client, "GET", path, nil, function(response)
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
    for _, memo in ipairs(payload.memos) do
      if type(memo) == "table" then
        table.insert(memos, {
          name = if type(memo.name) == "string" then memo.name else "",
          content = if type(memo.content) == "string" then memo.content else "",
          createTime = if type(memo.createTime) == "string" then memo.createTime else "",
          visibility = if type(memo.visibility) == "string" then memo.visibility else "",
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
    if line == ": connected" then
      reconnectAttempt = 0
      publishConnection("connected", "connected")
      fetchMemos()
      fetchReminders()
      return
    elseif line == ": heartbeat" then
      reconnectAttempt = 0
      publishConnection("connected", "connected")
      return
    end
    if string.sub(line, 1, 5) ~= "data:" then
      return
    end

    local payload = noctalia.string.trim(string.sub(line, 6))
    local event = noctalia.json.decode(payload)
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
    fetchReminders()
    startStream()
  end)

  if not accepted then
    validationInFlight = false
    setConnectionFailure("request_rejected")
  end
end

local function createMemo(sequence, content, reminderTime)
  if not connected or client == nil then
    publishCapture("error", sequence, "not_connected")
    return
  end
  if type(content) ~= "string" or noctalia.string.trim(content) == "" then
    publishCapture("error", sequence, "empty_memo")
    return
  end

  local memo = {
    content = content,
    state = "NORMAL",
    visibility = "PRIVATE",
  }
  if type(reminderTime) == "string" and Reminder.fromRfc3339(reminderTime) ~= nil then
    memo.reminderTime = reminderTime
  end
  local body = noctalia.json.encode(memo)
  if body == nil then
    publishCapture("error", sequence, "encode_failed")
    return
  end

  publishCapture("sending", sequence)
  local accepted = Client.request(client, "POST", "/api/v1/memos", body, function(response)
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

local function handleCommand(command)
  if type(command) ~= "table" or type(command.action) ~= "string" then
    return
  end
  if command.action == "refresh" then
    if connected then
      fetchMemos()
      fetchReminders()
    else
      validateConnection()
    end
  elseif command.action == "credentials_changed" then
    validateConnection()
  elseif command.action == "create" then
    local sequence = tonumber(command.sequence) or 0
    local content = command.content
    local reminderTime = command.reminderTime
    noctalia.state.set("command", { action = "ack", sequence = sequence })
    createMemo(sequence, content, reminderTime)
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
