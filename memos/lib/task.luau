--!nonstrict

local Task = {}

local HTML_BLOCK_TAGS = {
  address = true,
  article = true,
  aside = true,
  base = true,
  basefont = true,
  blockquote = true,
  body = true,
  caption = true,
  center = true,
  col = true,
  colgroup = true,
  dd = true,
  details = true,
  dialog = true,
  dir = true,
  div = true,
  dl = true,
  dt = true,
  fieldset = true,
  figcaption = true,
  figure = true,
  footer = true,
  form = true,
  frame = true,
  frameset = true,
  h1 = true,
  h2 = true,
  h3 = true,
  h4 = true,
  h5 = true,
  h6 = true,
  head = true,
  header = true,
  hr = true,
  html = true,
  iframe = true,
  legend = true,
  li = true,
  link = true,
  main = true,
  menu = true,
  menuitem = true,
  nav = true,
  noframes = true,
  ol = true,
  optgroup = true,
  option = true,
  p = true,
  param = true,
  search = true,
  section = true,
  summary = true,
  table = true,
  tbody = true,
  td = true,
  tfoot = true,
  th = true,
  thead = true,
  title = true,
  tr = true,
  track = true,
  ul = true,
}

local HTML_RAW_TAGS = {
  pre = true,
  script = true,
  style = true,
  textarea = true,
}

local function indentationColumns(value)
  local columns = 0
  for index = 1, #value do
    if string.sub(value, index, index) == "\t" then
      columns = columns + 4 - (columns % 4)
    else
      columns = columns + 1
    end
  end
  return columns
end

local function leadingIndent(line)
  return string.match(line, "^([ \t]*)") or ""
end

local function listPrefix(line)
  local indent, marker, spacing = string.match(line, "^([ \t]*)([-+*])([ \t]+)")
  if indent ~= nil then
    return {
      contentStart = #indent + #marker + #spacing + 1,
      indent = indentationColumns(indent),
    }
  end

  local digits, delimiter
  indent, digits, delimiter, spacing = string.match(line, "^([ \t]*)(%d+)([.)])([ \t]+)")
  if indent == nil or #digits > 9 then
    return nil
  end
  return {
    contentStart = #indent + #digits + #delimiter + #spacing + 1,
    indent = indentationColumns(indent),
  }
end

local function stripBlockquotes(line)
  local position = 1
  local depth = 0
  while position <= #line do
    local remainder = string.sub(line, position)
    local spaces = string.match(remainder, "^( *)") or ""
    if #spaces > 3 or string.sub(remainder, #spaces + 1, #spaces + 1) ~= ">" then
      break
    end
    position = position + #spaces + 1
    local nextCharacter = string.sub(line, position, position)
    if nextCharacter == " " or nextCharacter == "\t" then
      position = position + 1
    end
    depth = depth + 1
  end
  return string.sub(line, position), position - 1, depth
end

local function fence(line, allowIndented)
  local indent, run = string.match(line, "^([ \t]*)([`~]+)")
  if indent == nil or (not allowIndented and indentationColumns(indent) > 3) or #run < 3 then
    return nil
  end
  local character = string.sub(run, 1, 1)
  for index = 2, #run do
    if string.sub(run, index, index) ~= character then
      return nil
    end
  end
  return {
    character = character,
    length = #run,
    rest = string.sub(line, #indent + #run + 1),
  }
end

local function hasParentList(contexts, indent)
  for _, contextIndent in ipairs(contexts) do
    if contextIndent < indent then
      return true
    end
  end
  return false
end

local function enterList(contexts, indent)
  local nextContexts = {}
  for _, contextIndent in ipairs(contexts) do
    if contextIndent < indent then
      table.insert(nextContexts, contextIndent)
    end
  end
  table.insert(nextContexts, indent)
  return nextContexts
end

local function continueLists(contexts, indent)
  local nextContexts = {}
  for _, contextIndent in ipairs(contexts) do
    if contextIndent < indent then
      table.insert(nextContexts, contextIndent)
    end
  end
  return nextContexts
end

local function fenceForLine(line, prefix, contexts)
  local possible = fence(line, false)
  if possible ~= nil then
    return possible
  end
  if prefix ~= nil then
    possible = fence(string.sub(line, prefix.contentStart), true)
    if possible ~= nil then
      return possible
    end
  end
  local indent = indentationColumns(leadingIndent(line))
  if hasParentList(contexts, indent) then
    return fence(line, true)
  end
  return nil
end

local function htmlBlockStart(source)
  local trimmed = string.gsub(source, "^[ \t]+", "")
  local lower = string.lower(trimmed)
  if string.sub(lower, 1, 4) == "<!--" then
    if string.find(lower, "-->", 5, true) ~= nil then return false end
    return { endMarker = "-->", endsOnBlank = false }
  elseif string.sub(lower, 1, 9) == "<![cdata[" then
    if string.find(lower, "]]>", 10, true) ~= nil then return false end
    return { endMarker = "]]>", endsOnBlank = false }
  elseif string.sub(lower, 1, 2) == "<?" then
    if string.find(lower, "?>", 3, true) ~= nil then return false end
    return { endMarker = "?>", endsOnBlank = false }
  elseif string.match(lower, "^<![a-z]") ~= nil then
    if string.find(lower, ">", 3, true) ~= nil then return false end
    return { endMarker = ">", endsOnBlank = false }
  end

  local closingTag = string.match(lower, "^</([A-Za-z][A-Za-z0-9-]*)%s*>%s*$")
  if closingTag ~= nil then
    return { endMarker = nil, endsOnBlank = true }
  end

  local tag = string.match(lower, "^<([A-Za-z][A-Za-z0-9-]*)")
  if tag == nil then return nil end
  local afterTag = string.sub(lower, #tag + 2, #tag + 2)
  if afterTag ~= ">" and afterTag ~= "/" and string.match(afterTag, "%s") == nil then
    return nil
  end
  if not HTML_BLOCK_TAGS[tag] and not HTML_RAW_TAGS[tag] then
    if string.match(lower, "^<[A-Za-z][A-Za-z0-9-]*[^>]*>%s*$") ~= nil then
      return { endMarker = nil, endsOnBlank = true }
    end
    return nil
  end
  local close = "</" .. tag
  if string.find(lower, close, 1, true) ~= nil or string.sub(lower, -2) == "/>" then
    return false
  end
  return {
    endMarker = close,
    endsOnBlank = not HTML_RAW_TAGS[tag],
  }
end

local function nearestParentList(contexts, indent)
  local nearest = nil
  for _, contextIndent in ipairs(contexts) do
    if contextIndent < indent and (nearest == nil or contextIndent > nearest) then
      nearest = contextIndent
    end
  end
  return nearest
end

local function fenceContainerEnded(openFence, line, quoteDepth, prefix)
  if quoteDepth < openFence.quoteDepth then
    return true
  end
  if openFence.listIndent == nil or line == "" then
    return false
  end
  if prefix ~= nil then
    return prefix.indent <= openFence.listIndent
  end
  return indentationColumns(leadingIndent(line)) <= openFence.listIndent
end

local function removeIndent(line, columns)
  local position = 1
  local removed = 0
  while position <= #line and removed < columns do
    local character = string.sub(line, position, position)
    if character == " " then
      removed = removed + 1
    elseif character == "\t" then
      removed = removed + 4 - (removed % 4)
    else
      break
    end
    position = position + 1
  end
  return string.sub(line, position)
end

local function continuationText(records)
  local minimumIndent = nil
  for _, record in ipairs(records) do
    if record.working ~= "" then
      local indent = indentationColumns(leadingIndent(record.working))
      if minimumIndent == nil or indent < minimumIndent then
        minimumIndent = indent
      end
    end
  end
  minimumIndent = minimumIndent or 0

  local rendered = {}
  for _, record in ipairs(records) do
    table.insert(rendered, removeIndent(record.working, minimumIndent))
  end
  return table.concat(rendered, "\n")
end

function Task.find(content)
  local tasks = {}
  if type(content) ~= "string" or content == "" then
    return tasks
  end

  local records = {}
  local cursor = 1
  local lineNumber = 0
  local openFence = nil
  local openHtml = nil
  local listContexts = {}

  while cursor <= #content do
    local newlineStart = string.find(content, "\n", cursor, true)
    local rawEnd = #content
    if newlineStart ~= nil then
      rawEnd = newlineStart - 1
    end
    local lineEnd = rawEnd
    if lineEnd >= cursor and string.sub(content, lineEnd, lineEnd) == "\r" then
      lineEnd = lineEnd - 1
    end
    local line = ""
    if lineEnd >= cursor then
      line = string.sub(content, cursor, lineEnd)
    end
    local nextLineStart = #content + 1
    if newlineStart ~= nil then
      nextLineStart = newlineStart + 1
    end

    local working, quoteOffset, quoteDepth = stripBlockquotes(line)
    local prefix = listPrefix(working)
    local record = {
      line = line,
      working = working,
      quoteDepth = quoteDepth,
      prefix = prefix,
      lineStart = cursor,
      nextLineStart = nextLineStart,
    }
    table.insert(records, record)

    if openHtml ~= nil
      and (quoteDepth < openHtml.quoteDepth or (openHtml.endsOnBlank and working == ""))
    then
      openHtml = nil
    end
    if openFence ~= nil and fenceContainerEnded(openFence, working, quoteDepth, prefix) then
      openFence = nil
    end

    if openHtml ~= nil then
      if openHtml.endMarker ~= nil
        and string.find(string.lower(working), openHtml.endMarker, 1, true) ~= nil
      then
        openHtml = nil
      end
    elseif openFence ~= nil then
      local possibleFence = fence(working, true)
      if possibleFence ~= nil
        and possibleFence.character == openFence.character
        and possibleFence.length >= openFence.length
        and string.match(possibleFence.rest, "^[ \t]*$") ~= nil
      then
        openFence = nil
      end
    else
      local possibleFence = fenceForLine(working, prefix, listContexts)
      local htmlSource = working
      if prefix ~= nil then
        htmlSource = string.sub(working, prefix.contentStart)
      end
      local possibleHtml = htmlBlockStart(htmlSource)

      if possibleFence ~= nil then
        possibleFence.quoteDepth = quoteDepth
        possibleFence.listIndent = nil
        if prefix ~= nil and (prefix.indent < 4 or hasParentList(listContexts, prefix.indent)) then
          possibleFence.listIndent = prefix.indent
          listContexts = enterList(listContexts, prefix.indent)
        else
          local lineIndent = indentationColumns(leadingIndent(working))
          possibleFence.listIndent = nearestParentList(listContexts, lineIndent)
        end
        openFence = possibleFence
      elseif possibleHtml ~= nil then
        if possibleHtml ~= false then
          possibleHtml.quoteDepth = quoteDepth
          openHtml = possibleHtml
        end
      elseif prefix ~= nil then
        local belongsToList = prefix.indent < 4 or hasParentList(listContexts, prefix.indent)
        if belongsToList then
          local taskSource = string.sub(working, prefix.contentStart)
          local marker = string.match(taskSource, "^%[([ xX])%]")
          if marker ~= nil then
            local afterMarker = prefix.contentStart + 3
            local nextCharacter = string.sub(working, afterMarker, afterMarker)
            if nextCharacter == "" or nextCharacter == " " or nextCharacter == "\t" then
              local textStart = afterMarker
              while textStart <= #working do
                local character = string.sub(working, textStart, textStart)
                if character ~= " " and character ~= "\t" then
                  break
                end
                textStart = textStart + 1
              end
              local markerStart = cursor + quoteOffset + prefix.contentStart
              local task = {
                markerStart = markerStart,
                markerEnd = markerStart + 1,
                checked = marker == "x" or marker == "X",
                line = lineNumber,
                lineStart = cursor,
                nextLineStart = nextLineStart,
                continuationEnd = nextLineStart,
                continuationText = "",
                indent = prefix.indent,
                sourceIndent = prefix.indent,
                quoteDepth = quoteDepth,
                text = string.sub(working, textStart),
                recordIndex = #records,
              }
              table.insert(tasks, task)
              record.task = task
            end
          end
          listContexts = enterList(listContexts, prefix.indent)
        else
          listContexts = continueLists(listContexts, prefix.indent)
        end
      elseif working ~= "" then
        listContexts = continueLists(listContexts, indentationColumns(leadingIndent(working)))
      end
    end

    cursor = nextLineStart
    lineNumber = lineNumber + 1
  end

  for _, task in ipairs(tasks) do
    local continuation = {}
    local endPosition = task.nextLineStart
    for index = task.recordIndex + 1, #records do
      local record = records[index]
      if record.task ~= nil or record.quoteDepth < task.quoteDepth then
        break
      end
      if record.working ~= "" then
        local recordIndent = indentationColumns(leadingIndent(record.working))
        if record.quoteDepth == task.quoteDepth
          and ((record.prefix ~= nil and record.prefix.indent <= task.sourceIndent)
            or (record.prefix == nil and recordIndent <= task.sourceIndent))
        then
          break
        end
      end
      table.insert(continuation, record)
      endPosition = record.nextLineStart
    end
    task.continuationEnd = endPosition
    task.continuationText = continuationText(continuation)
    task.recordIndex = nil
    task.sourceIndent = nil
  end

  return tasks
end

function Task.renderFragment(content)
  if type(content) ~= "string" or content == "" then
    return content, 0
  end
  local firstLine = nil
  for line in string.gmatch(content, "[^\r\n]+") do
    if string.match(line, "^[ \t]*$") == nil then
      firstLine = line
      break
    end
  end
  if firstLine == nil then
    return content, 0
  end
  local prefix = listPrefix(firstLine)
  if prefix == nil or prefix.indent == 0 then
    return content, 0
  end

  local rendered = {}
  local cursor = 1
  while cursor <= #content do
    local newlineStart = string.find(content, "\n", cursor, true)
    local lineEnd = #content
    if newlineStart ~= nil then lineEnd = newlineStart - 1 end
    local line = string.sub(content, cursor, lineEnd)
    table.insert(rendered, removeIndent(line, prefix.indent))
    if newlineStart ~= nil then
      table.insert(rendered, "\n")
      cursor = newlineStart + 1
    else
      cursor = #content + 1
    end
  end
  return table.concat(rendered), prefix.indent
end

function Task.renderFragments(content)
  if type(content) ~= "string" or content == "" then
    return {}
  end

  local chunks = {}
  local current = {}
  local baseIndent = nil
  local cursor = 1
  local function flush()
    if #current == 0 then return end
    local text, indent = Task.renderFragment(table.concat(current))
    table.insert(chunks, { text = text, indent = indent })
    current = {}
    baseIndent = nil
  end

  while cursor <= #content do
    local newlineStart = string.find(content, "\n", cursor, true)
    local lineEnd = #content
    if newlineStart ~= nil then lineEnd = newlineStart - 1 end
    local line = string.sub(content, cursor, lineEnd)
    local comparisonLine = string.gsub(line, "\r$", "")
    if comparisonLine ~= "" then
      local prefix = listPrefix(comparisonLine)
      local lineIndent = indentationColumns(leadingIndent(comparisonLine))
      if prefix ~= nil then lineIndent = prefix.indent end
      if baseIndent == nil then
        baseIndent = lineIndent
      elseif baseIndent > 0 and lineIndent < baseIndent then
        flush()
        baseIndent = lineIndent
      end
    end
    table.insert(current, line)
    if newlineStart ~= nil then
      table.insert(current, "\n")
      cursor = newlineStart + 1
    else
      cursor = #content + 1
    end
  end
  flush()
  return chunks
end

function Task.replaceMarker(content, reference, checked)
  if type(content) ~= "string" or type(reference) ~= "table" or type(checked) ~= "boolean" then
    return nil, "invalid_task"
  end
  local markerStart = tonumber(reference.markerStart)
  local markerEnd = tonumber(reference.markerEnd)
  local line = tonumber(reference.line)
  if markerStart == nil or markerEnd == nil or line == nil
    or markerStart % 1 ~= 0 or markerEnd % 1 ~= 0 or line % 1 ~= 0
    or markerStart < 1 or markerEnd ~= markerStart + 1 or markerEnd > #content + 1
    or type(reference.checked) ~= "boolean"
  then
    return nil, "invalid_task"
  end

  local matched = nil
  for _, task in ipairs(Task.find(content)) do
    if task.markerStart == markerStart and task.markerEnd == markerEnd and task.line == line then
      matched = task
      break
    end
  end
  if matched == nil or matched.checked ~= reference.checked then
    return nil, "invalid_task"
  end
  if matched.checked == checked then
    return content, nil
  end

  local marker = " "
  if checked then
    marker = "x"
  end
  return string.sub(content, 1, markerStart - 1) .. marker .. string.sub(content, markerEnd), nil
end

return Task
