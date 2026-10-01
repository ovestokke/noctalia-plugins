-- Plain-text link detector. Keep aligned with Nodus client-links contract v1.
-- No rendering, network requests, Markdown interpretation or stored-text changes.
local links = {}

local function whitespace(c)
  return (c >= 9 and c <= 13) or c == 32 or c == 0xa0 or c == 0x1680
    or (c >= 0x2000 and c <= 0x200a) or c == 0x2028 or c == 0x2029
    or c == 0x202f or c == 0x205f or c == 0x3000 or c == 0xfeff
end

local boundaries = {}
for _, c in utf8.codes("([{<>\"'“‘,;!?") do boundaries[c] = true end
local delimiters = {}
for _, c in utf8.codes("<>\"'“”‘’`\\") do delimiters[c] = true end

local function delimiter(c)
  return whitespace(c) or c < 32 or (c >= 0x7f and c <= 0x9f) or delimiters[c] == true
end

local function bidi(c)
  return c == 0x061c or c == 0x200e or c == 0x200f
    or (c >= 0x202a and c <= 0x202e) or (c >= 0x2066 and c <= 0x2069)
end

local function validPort(port)
  if port == nil then return true end
  if #port < 1 or #port > 5 or not string.match(port, "^%d+$") then return false end
  local number = tonumber(port)
  return number >= 1 and number <= 65535
end

function links.isSafeHttpUrl(value)
  if type(value) ~= "string" or utf8.len(value) == nil then return false end
  for _, c in utf8.codes(value) do
    if delimiter(c) or bidi(c) then return false end
  end
  local authority = string.match(value, "^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]+)")
  if authority == nil then return false end
  if string.sub(authority, 1, 1) == "[" then
    local host, suffix = string.match(authority, "^%[([0-9a-fA-F:%.]+)%](.*)$")
    if host == nil or not string.find(host, ":", 1, true) then return false end
    if suffix == "" then return true end
    local port = string.match(suffix, "^:(%d+)$")
    return port ~= nil and validPort(port)
  end
  local host, port = string.match(authority, "^(.-):(%d+)$")
  host = host or authority
  if host == "" or string.match(host, "^[.%-]+$") then return false end
  for _, c in utf8.codes(host) do
    if c < 128 and not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122)
      or (c >= 48 and c <= 57) or c == 46 or c == 45) then return false end
  end
  return validPort(port)
end

local function trimProse(candidate)
  local balances = { [")"] = 0, ["]"] = 0, ["}"] = 0 }
  local pairs = { ["("] = ")", ["["] = "]", ["{"] = "}" }
  for i = 1, #candidate do
    local c = string.sub(candidate, i, i)
    if pairs[c] then balances[pairs[c]] = balances[pairs[c]] + 1
    elseif balances[c] then balances[c] = balances[c] - 1 end
  end
  local last = #candidate
  while last > 0 do
    local c = string.sub(candidate, last, last)
    if string.find(".,!?;:", c, 1, true) then last = last - 1
    elseif balances[c] and balances[c] < 0 then
      balances[c] = balances[c] + 1
      last = last - 1
    else break end
  end
  return string.sub(candidate, 1, last)
end

function links.segments(text)
  if text == "" then return {} end
  if utf8.len(text) == nil then return { { text = text } } end
  local out, offset = {}, 1
  local start, allowed, previous = nil, false, nil
  local function finish(last)
    if allowed then
      local href = trimProse(string.sub(text, start, last))
      if links.isSafeHttpUrl(href) then
        if start > offset then table.insert(out, { text = string.sub(text, offset, start - 1) }) end
        table.insert(out, { text = href, href = href })
        offset = start + #href
      end
    end
    start = nil
  end
  for pos, c in utf8.codes(text) do
    if start ~= nil then
      if delimiter(c) then finish(pos - 1) end
    elseif c == 72 or c == 104 then
      local prefix = string.lower(string.sub(text, pos, pos + 7))
      if prefix == "https://" or string.sub(prefix, 1, 7) == "http://" then
        start = pos
        allowed = previous == nil or whitespace(previous) or boundaries[previous] == true
      end
    end
    previous = c
  end
  if start ~= nil then finish(#text) end
  if offset <= #text then table.insert(out, { text = string.sub(text, offset) }) end
  return out
end

return links
