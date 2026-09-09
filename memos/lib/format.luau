--!nonstrict

local Reminder = require("./reminder.luau")

local Format = {}

function Format.memoTime(value)
  local epoch = Reminder.fromRfc3339(value)
  if epoch == nil then
    return if type(value) == "string" then value else ""
  end
  return noctalia.tr("time.timestamp", {
    date = os.date("%Y-%m-%d", epoch),
    time = os.date("%H:%M", epoch),
  })
end

function Format.reminderTime(value)
  local epoch = Reminder.fromRfc3339(value)
  if epoch == nil then
    return ""
  end
  return Reminder.localLabel(epoch)
end

function Format.visibility(value)
  if value == "PRIVATE" then
    return noctalia.tr("visibility.private")
  elseif value == "PROTECTED" then
    return noctalia.tr("visibility.protected")
  elseif value == "PUBLIC" then
    return noctalia.tr("visibility.public")
  elseif value == "SPACE" then
    return noctalia.tr("visibility.space")
  end
  return noctalia.tr("visibility.unknown")
end

return Format
