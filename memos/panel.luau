--!nonstrict

local Format = require("./lib/format.luau")
local Reminder = require("./lib/reminder.luau")

local connection = noctalia.state.get("connection") or {
  state = "unconfigured",
  sse = "disconnected",
}
local memos = noctalia.state.get("memos") or {}
local spaces = noctalia.state.get("spaces") or { items = {}, selected = "", revision = 0, state = "loading" }
local capture = noctalia.state.get("capture") or { state = "idle", sequence = 0, error = "" }
local editingName = nil
local editDraft = ""
local editKey = 0
local mutation = noctalia.state.get("mutation") or { state = "idle", error = "" }
local pendingMutation = nil
local draft = ""
local draftKey = 0
local reminderEpoch = nil
local reminderPreset = ""
local showCustomReminder = false
local showReminderEditor = false
local customReminderDate = ""
local customReminderTime = ""
local customReminderKey = 0
local reminderError = ""
local commandSequence = 0
local pendingSequence = nil
local isOpen = false
local view = "main"
local credentialDraft = ""
local credentialKey = 0
local credentialBusy = false
local credentialStatus = "idle"
local credentialError = ""
local render: () -> ()
local saveCredential: (any) -> ()
local submitMemo: (any) -> ()

local function connectionText()
  if connection.state ~= "connected" then
    return noctalia.tr("status." .. tostring(connection.state))
  end
  if connection.sse == "connected" then
    return noctalia.tr("status.connected")
  elseif connection.sse == "connecting" then
    return noctalia.tr("status.live_connecting")
  end
  return noctalia.tr("status.live_reconnecting")
end

local function connectionColor()
  if connection.state == "connected" and connection.sse == "connected" then
    return "primary"
  elseif connection.state == "connecting" or connection.sse == "connecting" or connection.sse == "reconnecting" then
    return "secondary"
  end
  return "error"
end

local function connectionHealthy()
  return connection.state == "connected" and connection.sse == "connected"
end

local function connectionBanner(visible)
  return ui.row({
    visible = visible,
    gap = 8,
    align = "center",
    padding = 10,
    fill = connectionColor() .. "/0.12",
    radius = 8,
  }, {
    ui.box({ width = 8, height = 8, radius = 4, fill = connectionColor() }),
    ui.label({ text = connectionText(), color = "on_surface", flexGrow = 1 }),
  })
end

local function captureText()
  if capture.state == "sending" then
    return noctalia.tr("capture.sending")
  elseif capture.state == "success" then
    return noctalia.tr("capture.saved")
  elseif capture.state == "error" then
    return noctalia.tr("capture.errors." .. tostring(capture.error))
  end
  return ""
end

local function externalTokenSelected()
  local path = noctalia.getConfig("token_file")
  return type(path) == "string" and noctalia.string.trim(path) ~= ""
end

local function shellQuote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function credentialMessage()
  if externalTokenSelected() then
    return noctalia.tr("credentials.external_selected")
  elseif credentialStatus == "saving" then
    return noctalia.tr("credentials.saving")
  elseif credentialStatus == "saved" then
    return noctalia.tr("credentials.saved")
  elseif credentialStatus == "error" then
    return noctalia.tr("credentials.errors." .. credentialError)
  end
  return noctalia.tr("credentials.help")
end

local function credentialEditor()
  local external = externalTokenSelected()
  return ui.column({
    gap = 8,
    padding = 10,
    fill = "surface_variant/0.35",
    radius = 8,
    border = "outline/0.35",
    borderWidth = 1,
  }, {
    ui.label({ text = noctalia.tr("credentials.title"), fontWeight = "semibold", color = "on_surface" }),
    ui.input({
      key = "credential-" .. tostring(credentialKey),
      value = credentialDraft,
      placeholder = noctalia.tr("credentials.placeholder"),
      password = true,
      focus = true,
      enabled = not credentialBusy and not external,
      onChange = function(value)
        credentialDraft = if type(value) == "string" then value else ""
        render()
      end,
      onSubmit = function(value)
        saveCredential(value)
      end,
    }),
    ui.row({ gap = 8, align = "center", justify = "space_between" }, {
      ui.label({
        text = credentialMessage(),
        color = if credentialStatus == "error" or external then "error" else "on_surface_variant",
        fontSize = 11,
        flexGrow = 1,
      }),
      ui.button({
        text = noctalia.tr("credentials.save"),
        glyph = "shield-lock",
        variant = "secondary",
        enabled = not credentialBusy and not external and noctalia.string.trim(credentialDraft) ~= "",
        onClick = function()
          saveCredential(credentialDraft)
        end,
      }),
    }),
  })
end

local REMINDER_PRESETS = {
  { key = "0700", hour = 7, label = "reminders.presets.0700" },
  { key = "1200", hour = 12, label = "reminders.presets.1200" },
  { key = "1600", hour = 16, label = "reminders.presets.1600" },
  { key = "2000", hour = 20, label = "reminders.presets.2000" },
}

local function setReminderPreset(preset)
  reminderEpoch = Reminder.nextLocalHour(preset.hour, os.time())
  reminderPreset = preset.key
  showCustomReminder = false
  showReminderEditor = false
  reminderError = ""
  render()
end

local function openCustomReminder()
  local initial = os.time() + 5 * 60
  customReminderDate = os.date("%Y-%m-%d", initial)
  customReminderTime = os.date("%H:%M", initial)
  customReminderKey += 1
  showCustomReminder = true
  reminderPreset = ""
  reminderError = ""
  render()
end

local function applyCustomReminder()
  local epoch, errorCode = Reminder.parseLocal(customReminderDate, customReminderTime, os.time())
  if epoch == nil then
    reminderError = errorCode or "invalid"
    render()
    return
  end
  reminderEpoch = epoch
  reminderPreset = "custom"
  showCustomReminder = false
  showReminderEditor = false
  reminderError = ""
  render()
end

local function clearReminder()
  reminderEpoch = nil
  reminderPreset = ""
  showCustomReminder = false
  reminderError = ""
  render()
end

local function reminderEditor()
  local presetButtons = {}
  for _, preset in ipairs(REMINDER_PRESETS) do
    table.insert(presetButtons, ui.button({
      text = noctalia.tr(preset.label),
      variant = "ghost",
      selected = reminderPreset == preset.key,
      onClick = function()
        setReminderPreset(preset)
      end,
    }))
  end

  return ui.column({ gap = 7 }, {
    ui.row({ gap = 8, align = "center", justify = "space_between" }, {
      ui.label({ text = noctalia.tr("reminders.title"), fontWeight = "semibold", color = "on_surface" }),
      ui.row({ gap = 4, align = "center" }, {
        ui.button({
          glyph = "calendar-clock",
          variant = "ghost",
          selected = showCustomReminder or reminderPreset == "custom",
          tooltip = noctalia.tr("reminders.custom.open"),
          onClick = openCustomReminder,
        }),
        ui.button({
          visible = reminderEpoch ~= nil,
          glyph = "x",
          variant = "ghost",
          tooltip = noctalia.tr("reminders.clear"),
          onClick = clearReminder,
        }),
      }),
    }),
    ui.row({ gap = 5, align = "center" }, presetButtons),
    ui.column({ visible = showCustomReminder, gap = 7 }, {
      ui.row({ gap = 7, align = "end" }, {
        ui.column({ gap = 4, flexGrow = 1 }, {
          ui.label({ text = noctalia.tr("reminders.custom.date"), fontSize = 11, color = "on_surface_variant" }),
          ui.input({
            key = "reminder-date-" .. tostring(customReminderKey),
            value = customReminderDate,
            placeholder = noctalia.tr("reminders.custom.date_placeholder"),
            onChange = function(value)
              customReminderDate = if type(value) == "string" then value else ""
            end,
          }),
        }),
        ui.column({ gap = 4, width = 104 }, {
          ui.label({ text = noctalia.tr("reminders.custom.time"), fontSize = 11, color = "on_surface_variant" }),
          ui.input({
            key = "reminder-time-" .. tostring(customReminderKey),
            value = customReminderTime,
            placeholder = noctalia.tr("reminders.custom.time_placeholder"),
            onChange = function(value)
              customReminderTime = if type(value) == "string" then value else ""
            end,
            onSubmit = function()
              applyCustomReminder()
            end,
          }),
        }),
        ui.button({
          text = noctalia.tr("reminders.custom.apply"),
          variant = "secondary",
          onClick = applyCustomReminder,
        }),
      }),
    }),
    ui.label({
      text = if reminderError ~= ""
        then noctalia.tr("reminders.errors." .. reminderError)
        elseif reminderEpoch ~= nil
        then noctalia.tr("reminders.selected", { time = Reminder.localLabel(reminderEpoch) })
        else noctalia.tr("reminders.none"),
      color = if reminderError ~= "" then "error" else "on_surface_variant",
      fontSize = 11,
    }),
  })
end

local function settingsView()
  return ui.column({ flexGrow = 1, gap = 14 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.button({
        glyph = "arrow-left",
        variant = "ghost",
        tooltip = noctalia.tr("actions.back"),
        onClick = "onSettingsBackClicked",
      }),
      ui.label({
        text = noctalia.tr("settings.title"),
        fontSize = 16,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.button({
        glyph = "close",
        variant = "ghost",
        tooltip = noctalia.tr("actions.close"),
        onClick = "onCloseClicked",
      }),
    }),

    connectionBanner(true),

    ui.column({ gap = 8, padding = 10, fill = "surface_variant/0.35", radius = 8 }, {
      ui.label({
        text = noctalia.tr("settings.connection.title"),
        fontWeight = "semibold",
        color = "on_surface",
      }),
      ui.label({
        text = noctalia.tr("settings.connection.description"),
        color = "on_surface_variant",
        fontSize = 11,
      }),
      ui.button({
        text = noctalia.tr("settings.connection.open"),
        glyph = "settings",
        variant = "secondary",
        onClick = "onNoctaliaSettingsClicked",
      }),
    }),

    credentialEditor(),
  })
end

local function submitMutation(action, name, pinned)
  if mutation.state == "sending" or connection.state ~= "connected" then
    return
  end
  commandSequence += 1
  pendingMutation = commandSequence
  mutation = { state = "sending", error = "" }
  render()
  noctalia.state.set("command", {
    action = action,
    name = name,
    pinned = pinned,
    content = if action == "update" then editDraft else nil,
    sequence = commandSequence,
  })
end

local function memoActions(memo)
  local busy = mutation.state == "sending"
  local canAct = memo.canEdit == true and not busy and connection.state == "connected" and memo.name ~= "" and editingName == nil
  return ui.column({ gap = 8 }, {
    ui.row({ gap = 8 }, {
      ui.button({
        tooltip = noctalia.tr(if memo.pinned then "crud.unpin" else "crud.pin"),
        glyph = "pin", variant = "ghost", selected = memo.pinned == true, enabled = canAct,
        onClick = function() submitMutation("pin", memo.name, not memo.pinned) end,
      }),
      ui.button({
        tooltip = noctalia.tr("crud.edit"), glyph = "pencil", variant = "ghost", enabled = canAct,
        onClick = function()
          editingName = memo.name
          editDraft = memo.content
          editKey += 1
          mutation = { state = "idle", error = "" }
          render()
        end,
      }),
      ui.button({
        tooltip = noctalia.tr("crud.archive"), glyph = "archive", variant = "ghost", enabled = canAct,
        onClick = function() submitMutation("archive", memo.name) end,
      }),
    }),
    ui.column({ visible = editingName == memo.name, gap = 8 }, {
      ui.input({
        key = "edit-" .. memo.name .. "-" .. tostring(editKey),
        value = editDraft, multiline = true, submitOnEnter = false, height = 140,
        enabled = not busy,
        onChange = function(value)
          editDraft = if type(value) == "string" then value else ""
          render()
        end,
        onSubmit = function()
          if noctalia.string.trim(editDraft) ~= "" then
            submitMutation("update", memo.name)
          end
        end,
      }),
      ui.row({ gap = 8 }, {
        ui.button({
          text = noctalia.tr("crud.save"), variant = "primary",
          enabled = not busy and connection.state == "connected" and noctalia.string.trim(editDraft) ~= "",
          onClick = function() submitMutation("update", memo.name) end,
        }),
        ui.button({
          text = noctalia.tr("crud.cancel"), variant = "ghost", enabled = not busy,
          onClick = function() editingName = nil; render() end,
        }),
      }),
    }),
  })
end

local function memoRows()
  local rows = {}
  if #memos == 0 then
    table.insert(rows, ui.column({ gap = 8, paddingV = 24, align = "center" }, {
      ui.glyph({ name = "notes-off", size = 28, color = "on_surface_variant" }),
      ui.label({ text = noctalia.tr("memos.empty"), color = "on_surface_variant", textAlign = "center" }),
    }))
    return rows
  end

  for index, memo in ipairs(memos) do
    local content = if type(memo.content) == "string" and memo.content ~= ""
      then memo.content
      else noctalia.tr("memos.empty_content")
    table.insert(rows, ui.column({
      key = if type(memo.name) == "string" and memo.name ~= "" then memo.name else "memo-" .. tostring(index),
      gap = 8,
      padding = 12,
      fill = "surface_variant/0.45",
      radius = 10,
      border = "outline/0.35",
      borderWidth = 1,
    }, {
      ui.row({ gap = 8, align = "center", justify = "space_between" }, {
        ui.label({
          text = Format.memoTime(memo.createTime),
          color = "on_surface_variant",
          fontSize = 11,
          flexGrow = 1,
        }),
        ui.label({
          text = Format.visibility(memo.visibility),
          color = "on_surface_variant",
          fontSize = 11,
        }),
      }),
      ui.label({
        visible = type(memo.reminderTime) == "string" and memo.reminderTime ~= "",
        text = noctalia.tr("reminders.memo_time", { time = Format.reminderTime(memo.reminderTime) }),
        color = "secondary",
        fontSize = 11,
      }),
      ui.markdown({ visible = editingName ~= memo.name, text = content }),
      memoActions(memo),
    }))
  end
  return rows
end

local function spacePicker()
  local options = { noctalia.tr("spaces.personal") }
  local names = { "" }
  local selectedIndex = 0
  local titleCounts = {}
  for _, space in ipairs(spaces.items) do
    local title = if type(space.title) == "string" and space.title ~= "" then space.title else noctalia.tr("spaces.untitled")
    titleCounts[title] = (titleCounts[title] or 0) + 1
  end
  local titleOccurrences = {}
  for _, space in ipairs(spaces.items) do
    local title = if type(space.title) == "string" and space.title ~= "" then space.title else noctalia.tr("spaces.untitled")
    titleOccurrences[title] = (titleOccurrences[title] or 0) + 1
    local label = if titleCounts[title] > 1 then title .. " (" .. tostring(titleOccurrences[title]) .. ")" else title
    table.insert(options, label)
    table.insert(names, space.name)
    if space.name == spaces.selected then selectedIndex = #options - 1 end
  end
  local found = spaces.selected == "" or names[selectedIndex + 1] == spaces.selected
  if not found then
    table.insert(options, noctalia.tr("spaces.unavailable_short"))
    table.insert(names, spaces.selected)
    selectedIndex = #options - 1
  end
  return ui.select({
      flexGrow = 1,
      controlSize = "sm",
      options = options,
      selectedIndex = selectedIndex,
      enabled = connection.state == "connected" and capture.state ~= "sending"
        and mutation.state ~= "sending" and editingName == nil,
      onChange = function(index, _text)
        local name = names[(tonumber(index) or -1) + 1]
        if name == nil or name == spaces.selected or capture.state == "sending" then return end
        commandSequence += 1
        noctalia.state.set("command", { action = "select_space", space = name, sequence = commandSequence })
      end,
    })
end

local function destinationReady()
  return spaces.selected == "" or spaces.state == "ready"
end

render = function()
  if not isOpen then
    return
  end

  if view == "settings" then
    panel.render(settingsView())
    return
  end

  local statusMessage = captureText()
  local connected = connection.state == "connected"
  local sending = capture.state == "sending"
  local canSubmit = connected and destinationReady() and not sending and noctalia.string.trim(draft) ~= ""

  panel.render(ui.column({ flexGrow = 1, gap = 10 }, {
    ui.row({ gap = 4, align = "center" }, {
      ui.glyph({ name = "notes", size = 19, color = "primary" }),
      spacePicker(),
      ui.button({
        glyph = "settings",
        variant = "ghost",
        tooltip = noctalia.tr("actions.settings"),
        onClick = "onSettingsClicked",
      }),
      ui.button({
        glyph = "refresh",
        variant = "ghost",
        tooltip = noctalia.tr("actions.refresh"),
        onClick = "onRefreshClicked",
      }),
      ui.button({ glyph = "close", variant = "ghost", tooltip = noctalia.tr("actions.close"), onClick = "onCloseClicked" }),
    }),

    connectionBanner(not connectionHealthy()),
    ui.label({
      visible = spaces.state == "error" or spaces.state == "unavailable" or spaces.state == "loading",
      text = noctalia.tr(if spaces.state == "error" then "spaces.error"
        elseif spaces.state == "unavailable" then "spaces.unavailable" else "spaces.loading"),
      color = if spaces.state == "loading" then "on_surface_variant" else "error",
      fontSize = 11,
    }),

    ui.column({ gap = 6 }, {
      ui.input({
        key = "capture-" .. tostring(draftKey),
        value = draft,
        placeholder = noctalia.tr("capture.placeholder"),
        multiline = true,
        submitOnEnter = false,
        height = 84,
        enabled = connected and not sending,
        onChange = function(value)
          draft = if type(value) == "string" then value else ""
          render()
        end,
        onSubmit = function(value)
          submitMemo(value)
        end,
      }),
      ui.row({ gap = 6, align = "center" }, {
        ui.button({
          glyph = "calendar-clock", variant = "ghost", controlSize = "sm",
          selected = showReminderEditor or reminderEpoch ~= nil,
          tooltip = noctalia.tr("reminders.title"),
          enabled = not sending,
          onClick = function()
            showReminderEditor = not showReminderEditor
            render()
          end,
        }),
        ui.label({
          text = noctalia.tr(if spaces.selected == "" then "spaces.private_short" else "spaces.shared_short"),
          color = "on_surface_variant", fontSize = 11, flexGrow = 1,
        }),
        ui.button({
          text = noctalia.tr("capture.save_short"),
          glyph = "send",
          variant = "primary",
          controlSize = "sm",
          tooltip = noctalia.tr("capture.shortcut"),
          enabled = canSubmit,
          onClick = function()
            submitMemo(draft)
          end,
        }),
      }),
      ui.column({ visible = showReminderEditor, gap = 6 }, { reminderEditor() }),
      ui.label({
        visible = reminderEpoch ~= nil and not showReminderEditor,
        text = noctalia.tr("reminders.selected", { time = Reminder.localLabel(reminderEpoch) }),
        color = "secondary", fontSize = 11,
      }),
      ui.label({
        visible = statusMessage ~= "",
        text = statusMessage,
        color = if capture.state == "error" then "error" else "on_surface_variant",
        fontSize = 11,
      }),
    }),

    ui.separator({ color = "outline/0.45" }),
    ui.label({
      visible = mutation.state == "error" or mutation.state == "sending",
      text = if mutation.state == "error" then noctalia.tr("crud.errors." .. mutation.error) else noctalia.tr("crud.sending"),
      color = if mutation.state == "error" then "error" else "on_surface_variant",
      fontSize = 11,
    }),
    ui.scroll({ flexGrow = 1, gap = 10 }, memoRows()),
  }))
end

noctalia.state.watch("connection", function(value)
  if type(value) == "table" then
    connection = value
    render()
  end
end)

noctalia.state.watch("spaces", function(value)
  if type(value) == "table" then
    spaces = value
    render()
  end
end)

noctalia.state.watch("memos", function(value)
  if type(value) == "table" then
    memos = value
    render()
  end
end)

noctalia.state.watch("mutation", function(value)
  if type(value) ~= "table" then return end
  mutation = value
  if pendingMutation ~= nil and value.sequence == pendingMutation and value.state ~= "sending" then
    pendingMutation = nil
    if value.state == "success" then
      editingName = nil
      editDraft = ""
    end
  end
  render()
end)

noctalia.state.watch("capture", function(value)
  if type(value) ~= "table" then
    return
  end
  capture = value
  if capture.state == "success" and pendingSequence ~= nil and capture.sequence == pendingSequence then
    draft = ""
    draftKey += 1
    reminderEpoch = nil
    reminderPreset = ""
    showCustomReminder = false
    showReminderEditor = false
    customReminderDate = ""
    customReminderTime = ""
    reminderError = ""
    pendingSequence = nil
  elseif capture.state == "error" and pendingSequence ~= nil and capture.sequence == pendingSequence then
    pendingSequence = nil
  end
  render()
end)

function onOpen(_context)
  isOpen = true
  connection = noctalia.state.get("connection") or connection
  memos = noctalia.state.get("memos") or memos
  capture = noctalia.state.get("capture") or capture
  spaces = noctalia.state.get("spaces") or spaces
  view = "main"
  render()
  commandSequence += 1
  noctalia.state.set("command", { action = "refresh", sequence = commandSequence })
end

function onClose()
  isOpen = false
end

saveCredential = function(value)
  if type(value) == "string" then
    credentialDraft = value
  end
  if credentialBusy or externalTokenSelected() then
    return
  end

  local token = noctalia.string.trim(credentialDraft)
  if token == "" then
    credentialStatus = "error"
    credentialError = "empty"
    render()
    return
  end

  local directory = noctalia.pluginDataDir()
  if type(directory) ~= "string" or directory == "" then
    credentialStatus = "error"
    credentialError = "storage"
    render()
    return
  end

  credentialBusy = true
  credentialStatus = "saving"
  credentialError = ""
  credentialDraft = ""
  credentialKey += 1
  render()

  local function fail(code)
    token = ""
    credentialBusy = false
    credentialStatus = "error"
    credentialError = code
    render()
  end

  local directoryModeAccepted = noctalia.runAsync("chmod 700 " .. shellQuote(directory), function(directoryResult)
    if type(directoryResult) ~= "table" or directoryResult.exitCode ~= 0 or directoryResult.timedOut then
      fail("permissions")
      return
    end

    local tokenPath = directory .. "/token"
    local written = noctalia.writeFile(tokenPath, token .. "\n")
    token = ""
    if not written then
      fail("write")
      return
    end

    local fileModeAccepted = noctalia.runAsync("chmod 600 " .. shellQuote(tokenPath), function(fileResult)
      if type(fileResult) ~= "table" or fileResult.exitCode ~= 0 or fileResult.timedOut then
        fail("permissions")
        return
      end
      credentialBusy = false
      credentialStatus = "saved"
      credentialError = ""
      render()
      commandSequence += 1
      noctalia.state.set("command", { action = "credentials_changed", sequence = commandSequence })
    end, 5000)
    if not fileModeAccepted then
      fail("permissions")
    end
  end, 5000)

  if not directoryModeAccepted then
    fail("permissions")
  end
end

submitMemo = function(value)
  if type(value) == "string" then
    draft = value
  end
  if connection.state ~= "connected" or not destinationReady() or capture.state == "sending" or noctalia.string.trim(draft) == "" then
    return
  end
  commandSequence += 1
  pendingSequence = commandSequence
  capture = { state = "sending", sequence = commandSequence }
  render()
  noctalia.state.set("command", {
    action = "create",
    space = spaces.selected,
    scopeRevision = spaces.revision,
    sequence = commandSequence,
    content = draft,
    reminderTime = Reminder.toRfc3339(reminderEpoch),
  })
end

function onRefreshClicked()
  commandSequence += 1
  noctalia.state.set("command", { action = "refresh", sequence = commandSequence })
end

function onSettingsClicked()
  view = "settings"
  credentialDraft = ""
  credentialKey += 1
  credentialStatus = "idle"
  credentialError = ""
  render()
end

function onSettingsBackClicked()
  view = "main"
  render()
end

function onNoctaliaSettingsClicked()
  noctalia.openSettings()
end

function onCloseClicked()
  panel.close()
end
