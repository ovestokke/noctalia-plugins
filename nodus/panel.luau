--!nonstrict

local connection = noctalia.state.get("connection") or { state = "loading" }
local listing = noctalia.state.get("notes") or { items = {}, next = false, counts = {} }
local selected = noctalia.state.get("selected")
local selectedID = nil
local capture = noctalia.state.get("capture") or { state = "idle" }
local detailError = ""
local filter = "active"
local composerOpen = false
local composerKind = "text"
local discardConfirm = false
local titleDraft = ""
local textDraft = ""
local listTitleDraft = ""
local listDraftItems = { { key = 1, text = "" } }
local listRowKey = 1
local draftKey = 0
local pendingSequence = nil
local pendingCreateKind = nil
local pendingToggleItemID = nil
local pendingToggleTarget = nil
local sequence = 0
local isOpen = false
local hoveredID = nil
local render

local function command(action, extra)
  sequence += 1
  local data = extra or {}
  data.action = action
  data.sequence = sequence
  noctalia.state.set("command", data)
  return sequence
end

local function statusText()
  if connection.state == "connected" then return noctalia.tr("status.connected") end
  if connection.state == "offline" then return noctalia.tr("status.offline") end
  if connection.state == "rate_limited" then return noctalia.tr("status.rate_limited") end
  if connection.state == "auth" then return noctalia.tr("status.auth") end
  if connection.state == "unknown" or connection.state == "sending" then return noctalia.tr("status.unknown") end
  if connection.state == "conflict" then return noctalia.tr("status.conflict") end
  if connection.state == "loading" then return noctalia.tr("status.loading") end
  if connection.state == "unpaired" then return noctalia.tr("status.unpaired") end
  return noctalia.tr("status.error")
end

local function noteTitle(n)
  if type(n.title) == "string" and n.title ~= "" then return n.title end
  return noctalia.tr("notes.untitled")
end

local function dateLabel(value)
  if type(value) ~= "string" then return "" end
  local year, month, day = string.match(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if year == nil then return "" end
  if year == os.date("%Y") then return day .. "." .. month end
  return day .. "." .. month .. "." .. string.sub(year, 3)
end

local function header()
  local healthy = connection.state == "connected"
  return ui.row({ align = "center", gap = 8 }, {
    ui.label({ text = "Nodus", fontSize = 25, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
    ui.box({ width = 6, height = 6, radius = 3, fill = if healthy then "primary" else "on_surface_variant" }),
    ui.label({ text = if healthy then noctalia.tr("status.short_connected") else noctalia.tr("status.short_disconnected"),
      fontSize = 11, color = "on_surface_variant" }),
    ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("actions.refresh"),
      onClick = function() command("refresh") end }),
    ui.button({ glyph = "x", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("actions.close"),
      onClick = function() panel.close() end }),
  })
end

local function listHasContent()
  if listTitleDraft ~= "" then return true end
  for _, item in ipairs(listDraftItems) do if item.text ~= "" then return true end end
  return false
end

local function saveNote()
  if connection.state ~= "connected" or capture.state == "sending" then return end
  local title, text, items
  if composerKind == "checklist" then
    if not listHasContent() then return end
    title = listTitleDraft
    text = ""
    items = {}
    for _, item in ipairs(listDraftItems) do
      if item.text ~= "" then table.insert(items, item.text) end
    end
  else
    if titleDraft == "" and textDraft == "" then return end
    title, text = titleDraft, textDraft
  end
  pendingCreateKind = composerKind
  pendingSequence = command("create", { kind = composerKind, title = title, text = text, items = items })
  capture = { state = "sending", sequence = pendingSequence }
  render()
end

local function addDraftItem()
  if #listDraftItems >= 1000 then return end
  discardConfirm = false
  listRowKey += 1
  table.insert(listDraftItems, { key = listRowKey, text = "" })
  render()
end

local function discardDraft()
  local hasContent = if composerKind == "checklist" then listHasContent() else titleDraft ~= "" or textDraft ~= ""
  if hasContent and not discardConfirm then
    discardConfirm = true
    render()
    return
  end
  if composerKind == "checklist" then
    listTitleDraft = ""
    listRowKey += 1
    listDraftItems = { { key = listRowKey, text = "" } }
  else
    titleDraft = ""; textDraft = ""
  end
  draftKey += 1
  discardConfirm = false
  composerOpen = false
  render()
end

local function composer()
  return ui.row({ gap = 6, align = "center", paddingH = 10, paddingV = 6,
    fill = "surface_variant/0.42", border = "outline/0.32", borderWidth = 1, radius = 10 }, {
    ui.row({ gap = 12, align = "center", paddingH = 4, paddingV = 7, flexGrow = 1,
      onClick = function()
        if composerKind ~= "checklist" or not listHasContent() then composerKind = "text" end
        discardConfirm = false; composerOpen = true; render()
      end }, {
      ui.glyph({ name = "plus", size = 18, color = "primary" }),
      ui.label({ text = if composerKind == "checklist" and listHasContent() then noctalia.tr("compose.continue_list")
        elseif titleDraft ~= "" or textDraft ~= "" then noctalia.tr("compose.continue")
        else noctalia.tr("compose.heading"), fontSize = 14, color = "on_surface", flexGrow = 1 }),
    }),
    ui.box({ width = 1, height = 23, fill = "outline/0.4" }),
    ui.button({ glyph = "list-check", variant = "ghost", controlSize = "sm",
      tooltip = noctalia.tr("actions.new_list"),
      onClick = function() composerKind = "checklist"; discardConfirm = false; composerOpen = true; render() end }),
  })
end

local function editorActions()
  if discardConfirm then
    return ui.row({ gap = 8, align = "center", justify = "space_between" }, {
      ui.button({ text = noctalia.tr("actions.keep_editing"), variant = "ghost",
        onClick = function() discardConfirm = false; render() end }),
      ui.button({ text = noctalia.tr("actions.confirm_discard"), variant = "destructive", onClick = discardDraft }),
    })
  end
  local canSave = connection.state == "connected" and capture.state ~= "sending"
    and (if composerKind == "checklist" then listHasContent() else titleDraft ~= "" or textDraft ~= "")
  return ui.row({ gap = 8, align = "center", justify = "space_between" }, {
    ui.button({ text = noctalia.tr("actions.discard"), variant = "ghost",
      enabled = capture.state ~= "sending", onClick = discardDraft }),
    ui.button({ text = if composerKind == "checklist" then noctalia.tr("actions.save_list") else noctalia.tr("actions.save"),
      variant = "primary", enabled = canSave, onClick = saveNote }),
  })
end

local function editorView()
  local heading = ui.row({ gap = 10, align = "center" }, {
    ui.glyph({ name = if composerKind == "checklist" then "list-check" else "file-text", size = 20, color = "primary" }),
    ui.label({ text = if composerKind == "checklist" then noctalia.tr("compose.new_list") else noctalia.tr("compose.new_note"),
      fontSize = 20, fontWeight = "semibold", color = "on_surface", flexGrow = 1 }),
  })
  local offline = ui.label({ visible = connection.state ~= "connected", text = noctalia.tr("compose.offline"),
    fontSize = 11, color = "on_surface_variant" })

  if composerKind == "checklist" then
    local rows = {}
    for _, entry in ipairs(listDraftItems) do
      local item = entry
      table.insert(rows, ui.row({ key = "draft-row-" .. tostring(item.key), gap = 7, align = "center" }, {
        ui.glyph({ name = "square", size = 16, color = "on_surface_variant" }),
        ui.input({ key = "draft-item-" .. tostring(item.key), value = item.text, flexGrow = 1,
          placeholder = noctalia.tr("compose.list_item"), focus = item.key == listRowKey,
          onChange = function(value) item.text = value; discardConfirm = false; render() end,
          onSubmit = function(value) item.text = value; addDraftItem() end }),
        ui.button({ glyph = "x", variant = "ghost", controlSize = "sm",
          tooltip = noctalia.tr("actions.remove_draft_item"), enabled = #listDraftItems > 1,
          onClick = function()
            for index, row in ipairs(listDraftItems) do
              if row.key == item.key then table.remove(listDraftItems, index); break end
            end
            discardConfirm = false; render()
          end }),
      }))
    end
    return ui.column({ flexGrow = 1, gap = 13 }, {
      heading,
      ui.input({ key = "list-title-" .. tostring(draftKey), value = listTitleDraft,
        placeholder = noctalia.tr("compose.title"),
        onChange = function(value) listTitleDraft = value; discardConfirm = false; render() end }),
      ui.separator({ color = "outline/0.3" }),
      ui.scroll({ flexGrow = 1, gap = 7, paddingV = 4 }, rows),
      ui.button({ text = noctalia.tr("actions.add_item"), glyph = "plus", variant = "ghost",
        contentAlign = "start", controlSize = "sm", enabled = #listDraftItems < 1000,
        onClick = addDraftItem }),
      ui.separator({ color = "outline/0.3" }),
      editorActions(),
      offline,
    })
  end

  return ui.column({ flexGrow = 1, gap = 13 }, {
    heading,
    ui.input({ key = "title-" .. tostring(draftKey), value = titleDraft,
      placeholder = noctalia.tr("compose.title"),
      onChange = function(value) titleDraft = value; discardConfirm = false; render() end }),
    ui.input({ key = "body-" .. tostring(draftKey), value = textDraft, multiline = true,
      flexGrow = 1, focus = true, placeholder = noctalia.tr("compose.body"),
      onChange = function(value) textDraft = value; discardConfirm = false; render() end,
      onSubmit = function(value) textDraft = value; saveNote() end }),
    editorActions(),
    offline,
  })
end

local function tab(key, title, count)
  local active = filter == key
  return ui.column({ key = "tab-" .. key, gap = 5, paddingV = 5,
    onClick = function() filter = key; render() end }, {
    ui.row({ gap = 5, align = "center" }, {
      ui.label({ text = noctalia.tr(title), fontSize = 13,
        fontWeight = if active then "semibold" else "normal",
        color = if active then "on_surface" else "on_surface_variant" }),
      ui.label({ text = tostring(count), fontSize = 11, color = if active then "primary" else "on_surface_variant" }),
    }),
    ui.box({ height = 2, radius = 1, fill = if active then "primary" else "primary/0" }),
  })
end

local function tabs()
  local totals = listing.counts or {}
  return ui.row({ gap = 22, align = "center" }, {
    tab("active", "filters.active", totals.active or 0),
    tab("archive", "filters.archive", totals.archive or 0),
    tab("trash", "filters.trash", totals.trash or 0),
  })
end

local function belongs(n)
  if filter == "trash" then return n.state == "trash" end
  if filter == "archive" then return n.state == "live" and n.archived == true end
  return n.state == "live" and n.archived ~= true
end

local function notePreview(n)
  local preview = if type(n.preview) == "string" then n.preview else ""
  if n.kind ~= "checklist" then
    return if preview ~= "" then preview else noctalia.tr("notes.empty")
  end
  local progress = tostring(n.checked or 0) .. "/" .. tostring(n.items or 0)
  return if preview ~= "" then progress .. "  " .. preview else progress .. "  " .. noctalia.tr("notes.empty_checklist")
end

local function noteRow(n)
  return ui.column({ key = "note-" .. n.id, gap = 5, paddingH = 10, paddingV = 10, radius = 8,
    fill = if hoveredID == n.id then "surface_variant/0.48" else nil,
    onHover = function(state)
      if state == "true" then hoveredID = n.id; render()
      elseif hoveredID == n.id then hoveredID = nil; render() end
    end,
    onClick = function()
      selected = nil; selectedID = n.id; detailError = ""
      command("open", { id = n.id }); render()
    end }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.label({ text = noteTitle(n), fontSize = 14, fontWeight = "semibold",
        color = "on_surface", maxLines = 1, flexGrow = 1 }),
      ui.label({ text = dateLabel(n.updated), fontSize = 11, color = "on_surface_variant" }),
    }),
    ui.row({ gap = 7, align = "center" }, {
      ui.glyph({ visible = n.kind == "checklist", name = "list-check", size = 13, color = "on_surface_variant" }),
      ui.label({ text = notePreview(n), fontSize = 12, color = "on_surface_variant", maxLines = 1, flexGrow = 1 }),
    }),
  })
end

local function notesList()
  local rows = {}
  for _, n in ipairs(listing.items or {}) do
    if type(n) == "table" and belongs(n) then
      table.insert(rows, noteRow(n))
      table.insert(rows, ui.separator({ color = "outline/0.18", spacing = 0 }))
    end
  end
  if #rows == 0 then
    table.insert(rows, ui.column({ gap = 7, paddingV = 36, align = "center" }, {
      ui.label({ text = noctalia.tr("notes.none." .. filter), fontSize = 14, color = "on_surface_variant" }),
      ui.label({ text = if filter == "active" then noctalia.tr("notes.start") else "",
        fontSize = 12, color = "on_surface_variant" }),
    }))
  end
  if listing.next then table.insert(rows, ui.button({ text = noctalia.tr("actions.more"), variant = "ghost",
    onClick = function() command("more") end })) end
  return ui.scroll({ flexGrow = 1, gap = 0 }, rows)
end

local function setupView()
  return ui.column({ flexGrow = 1, gap = 13, padding = 16 }, {
    ui.glyph({ name = "shield-lock", size = 28, color = "primary" }),
    ui.label({ text = noctalia.tr("setup.heading"), fontSize = 20, fontWeight = "semibold", color = "on_surface" }),
    ui.label({ text = noctalia.tr("setup.web"), color = "on_surface_variant" }),
    ui.label({ text = noctalia.tr("setup.terminal"), color = "on_surface_variant" }),
    ui.label({ text = noctalia.tr("setup.finish"), color = "on_surface_variant" }),
  })
end

local function listView()
  if connection.state == "unpaired" then return setupView() end
  return ui.column({ flexGrow = 1, gap = 14 }, {
    composer(),
    tabs(),
    notesList(),
  })
end

local markdownChars = { ["\\"] = true, ["`"] = true, ["*"] = true, ["_"] = true,
  ["{"] = true, ["}"] = true, ["["] = true, ["]"] = true, ["("] = true,
  [")"] = true, ["#"] = true, ["+"] = true, ["-"] = true, ["."] = true,
  ["!"] = true, ["|"] = true, [">"] = true, ["<"] = true, ["~"] = true, ["&"] = true }
local function struckText(text)
  local source = if text ~= "" then text else noctalia.tr("notes.untitled_item")
  local escaped = {}
  for index = 1, #source do
    local character = string.sub(source, index, index)
    if character == "\n" or character == "\r" or character == "\t" then character = " " end
    if markdownChars[character] then table.insert(escaped, "\\") end
    table.insert(escaped, character)
  end
  return "~~" .. table.concat(escaped) .. "~~"
end

local function markChecked(item)
  if connection.state ~= "connected" or capture.state == "sending" or pendingToggleItemID ~= nil
    or selected == nil or selected.state ~= "live" or type(item.id) ~= "string"
    or type(item.revision) ~= "string" then return end
  pendingToggleItemID = item.id
  pendingToggleTarget = not item.checked
  pendingSequence = command("checked", { noteId = selectedID, itemId = item.id,
    revision = item.revision, checked = pendingToggleTarget })
  capture = { state = "sending", sequence = pendingSequence }
  render()
end

local function checklistRow(item)
  local checked = item.checked == true
  local label = if checked then ui.column({ flexGrow = 1, opacity = 0.65 }, {
    ui.markdown({ text = struckText(item.text or ""), flexGrow = 1 }),
  }) else ui.label({ text = if item.text ~= "" then item.text else noctalia.tr("notes.untitled_item"),
    fontSize = 14, color = "on_surface", flexGrow = 1 })
  return ui.row({ key = "item-" .. item.id, gap = 7, paddingV = 1, align = "start" }, {
    ui.button({ glyph = if checked then "square-check" else "square", variant = "ghost", controlSize = "sm",
      tooltip = if checked then noctalia.tr("actions.uncheck") else noctalia.tr("actions.check"),
      enabled = connection.state == "connected" and selected.state == "live" and pendingToggleItemID == nil,
      onClick = function() markChecked(item) end }),
    label,
  })
end

local function detailView()
  local contents = {}
  if selected ~= nil and selected.id == selectedID then
    table.insert(contents, ui.label({ text = noteTitle(selected), fontSize = 21,
      fontWeight = "semibold", color = "on_surface", maxLines = 3 }))
    table.insert(contents, ui.label({ text = dateLabel(selected.updated), fontSize = 11,
      color = "on_surface_variant" }))
    table.insert(contents, ui.separator({ color = "outline/0.32", spacing = 5 }))
    if detailError ~= "" then table.insert(contents, ui.label({ text = detailError, fontSize = 12, color = "error" })) end
    if selected.kind == "checklist" then
      local openItems, completedItems = {}, {}
      for _, item in ipairs(selected.items or {}) do
        if item.deleted ~= true then
          if item.checked then table.insert(completedItems, item)
          else table.insert(openItems, item) end
        end
      end
      local function byPosition(a, b)
        if a.position ~= b.position then return (a.position or 0) < (b.position or 0) end
        return tostring(a.id) < tostring(b.id)
      end
      table.sort(openItems, byPosition)
      table.sort(completedItems, byPosition)
      for _, item in ipairs(openItems) do table.insert(contents, checklistRow(item)) end
      if #openItems > 0 and #completedItems > 0 then
        table.insert(contents, ui.separator({ color = "outline/0.5", spacing = 9 }))
      end
      for _, item in ipairs(completedItems) do table.insert(contents, checklistRow(item)) end
      if pendingToggleItemID ~= nil then table.insert(contents, ui.label({ text = noctalia.tr("status.checking"),
        fontSize = 11, color = "on_surface_variant" })) end
    else
      table.insert(contents, ui.label({ text = if selected.text ~= "" then selected.text else noctalia.tr("notes.empty"),
        fontSize = 14, color = "on_surface" }))
    end
  else
    table.insert(contents, ui.label({ text = if detailError ~= "" then detailError else noctalia.tr("status.loading"),
      color = "on_surface_variant" }))
  end
  return ui.column({ flexGrow = 1, gap = 10 }, {
    ui.row({ gap = 8, align = "center", justify = "space_between" }, {
      ui.button({ text = noctalia.tr("actions.back"), glyph = "arrow-left", variant = "ghost",
        contentAlign = "start", onClick = function() selected = nil; selectedID = nil; detailError = ""; render() end }),
      ui.button({ glyph = "refresh", variant = "ghost", controlSize = "sm", tooltip = noctalia.tr("actions.refresh_note"),
        enabled = selectedID ~= nil, onClick = function() command("open", { id = selectedID, fresh = true }) end }),
    }),
    ui.scroll({ flexGrow = 1, gap = 11, padding = 9 }, contents),
  })
end

render = function()
  if not isOpen then return end
  local warning = connection.message or ""
  local writeMessage = capture.message or ""
  local issue = connection.state ~= "connected" and connection.state ~= "loading"
  panel.render(ui.column({ flexGrow = 1, gap = 14, padding = 16 }, {
    header(),
    ui.label({ visible = issue, text = statusText(), fontSize = 12,
      color = if connection.state == "unknown" or connection.state == "conflict" then "error" else "on_surface_variant" }),
    ui.label({ visible = warning ~= "", text = warning, fontSize = 11,
      color = "on_surface_variant", maxLines = 3 }),
    ui.label({ visible = writeMessage ~= "", text = writeMessage, fontSize = 11,
      color = if capture.state == "error" then "error" else "primary", maxLines = 3 }),
    ui.button({ visible = connection.state == "unknown", text = noctalia.tr("actions.retry"), variant = "outline",
      onClick = function() command("retry") end }),
    if selectedID ~= nil then detailView() elseif composerOpen then editorView() else listView(),
  }))
end

noctalia.state.watch("connection", function(value) if type(value) == "table" then connection = value; render() end end)
noctalia.state.watch("notes", function(value) if type(value) == "table" then listing = value; render() end end)
noctalia.state.watch("selected", function(value)
  if type(value) ~= "table" then return end
  selected = value
  if pendingToggleItemID ~= nil and value.id == selectedID then
    for _, item in ipairs(value.items or {}) do
      if item.id == pendingToggleItemID and item.checked == pendingToggleTarget then
        pendingToggleItemID = nil; pendingToggleTarget = nil
        break
      end
    end
  end
  render()
end)
noctalia.state.watch("detailError", function(value) detailError = tostring(value or ""); render() end)
noctalia.state.watch("capture", function(value)
  if type(value) ~= "table" then return end
  capture = value
  if pendingSequence ~= nil and value.sequence == pendingSequence and value.state ~= "sending" then
    pendingSequence = nil
    if pendingCreateKind ~= nil then
      if value.state == "saved" then
        if pendingCreateKind == "checklist" then
          listTitleDraft = ""; listRowKey += 1
          listDraftItems = { { key = listRowKey, text = "" } }
        else titleDraft = ""; textDraft = "" end
        draftKey += 1; composerOpen = false; discardConfirm = false
      end
      pendingCreateKind = nil
    elseif value.state ~= "saved" then
      pendingToggleItemID = nil; pendingToggleTarget = nil
    end
  end
  render()
end)
function onOpen(_context)
  isOpen = true
  connection = noctalia.state.get("connection") or connection
  listing = noctalia.state.get("notes") or listing
  capture = noctalia.state.get("capture") or capture
  selected = nil
  selectedID = nil
  command("refresh")
  render()
end
function onClose() isOpen = false end
