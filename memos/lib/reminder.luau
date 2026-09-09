--!nonstrict

local Reminder = {}

local function isLeapYear(year)
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function daysInMonth(year, month)
  if month == 2 then
    return if isLeapYear(year) then 29 else 28
  elseif month == 4 or month == 6 or month == 9 or month == 11 then
    return 30
  end
  return 31
end

local function validDateTime(year, month, day, hour, minute, second)
  return year >= 1970
    and month >= 1
    and month <= 12
    and day >= 1
    and day <= daysInMonth(year, month)
    and hour >= 0
    and hour <= 23
    and minute >= 0
    and minute <= 59
    and second >= 0
    and second <= 59
end

local function utcEpoch(year, month, day, hour, minute, second)
  local adjustedYear = if month <= 2 then year - 1 else year
  local era = math.floor(adjustedYear / 400)
  local yearOfEra = adjustedYear - era * 400
  local adjustedMonth = month + if month > 2 then -3 else 9
  local dayOfYear = math.floor((153 * adjustedMonth + 2) / 5) + day - 1
  local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
  local daysSinceEpoch = era * 146097 + dayOfEra - 719468
  return daysSinceEpoch * 86400 + hour * 3600 + minute * 60 + second
end

local function localOffsetSeconds(epoch)
  local value = os.date("%z", epoch)
  local sign, hour, minute = string.match(value, "^([%+%-])(%d%d)(%d%d)$")
  hour = tonumber(hour)
  minute = tonumber(minute)
  if sign == nil or hour == nil or minute == nil then
    return nil
  end
  local offset = (hour * 60 + minute) * 60
  return if sign == "-" then -offset else offset
end

local function localEpoch(year, month, day, hour, minute, second)
  if not validDateTime(year, month, day, hour, minute, second) then
    return nil
  end
  local wallClockAsUtc = utcEpoch(year, month, day, hour, minute, second)
  local offset = localOffsetSeconds(wallClockAsUtc)
  if offset == nil then
    return nil
  end
  local epoch = wallClockAsUtc - offset
  local correctedOffset = localOffsetSeconds(epoch)
  if correctedOffset ~= nil and correctedOffset ~= offset then
    epoch = wallClockAsUtc - correctedOffset
  end
  local check = os.date("*t", epoch)
  if check.year ~= year
    or check.month ~= month
    or check.day ~= day
    or check.hour ~= hour
    or check.min ~= minute
    or check.sec ~= second
  then
    return nil
  end
  return epoch
end

function Reminder.fromRfc3339(value)
  if type(value) ~= "string" then
    return nil
  end

  local year, month, day, hour, minute, second, suffix = string.match(
    value,
    "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)[%.%d]*([Zz%+%-].*)$"
  )
  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  hour = tonumber(hour)
  minute = tonumber(minute)
  second = tonumber(second)
  if year == nil
    or month == nil
    or day == nil
    or hour == nil
    or minute == nil
    or second == nil
    or not validDateTime(year, month, day, hour, minute, second)
  then
    return nil
  end

  local offsetSeconds = 0
  if suffix ~= "Z" and suffix ~= "z" then
    local sign, offsetHour, offsetMinute = string.match(suffix, "^([%+%-])(%d%d):(%d%d)$")
    offsetHour = tonumber(offsetHour)
    offsetMinute = tonumber(offsetMinute)
    if sign == nil or offsetHour == nil or offsetHour > 23 or offsetMinute == nil or offsetMinute > 59 then
      return nil
    end
    offsetSeconds = (offsetHour * 60 + offsetMinute) * 60
    if sign == "-" then
      offsetSeconds = -offsetSeconds
    end
  end

  return utcEpoch(year, month, day, hour, minute, second) - offsetSeconds
end

function Reminder.toRfc3339(epoch)
  if type(epoch) ~= "number" then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

function Reminder.nextLocalHour(hour, now)
  if type(hour) ~= "number" or hour < 0 or hour > 23 then
    return nil
  end
  now = if type(now) == "number" then now else os.time()
  local parts = os.date("*t", now)
  local candidate = localEpoch(parts.year, parts.month, parts.day, hour, 0, 0)
  if candidate == nil then
    return nil
  end
  if candidate <= now then
    local nextDate = os.date("!*t", utcEpoch(parts.year, parts.month, parts.day, 12, 0, 0) + 86400)
    candidate = localEpoch(nextDate.year, nextDate.month, nextDate.day, hour, 0, 0)
  end
  return candidate
end

function Reminder.parseLocal(dateValue, timeValue, now)
  if type(dateValue) ~= "string" or type(timeValue) ~= "string" then
    return nil, "invalid"
  end
  local year, month, day = string.match(dateValue, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  local hour, minute = string.match(timeValue, "^(%d%d):(%d%d)$")
  year = tonumber(year)
  month = tonumber(month)
  day = tonumber(day)
  hour = tonumber(hour)
  minute = tonumber(minute)
  if year == nil
    or month == nil
    or day == nil
    or hour == nil
    or minute == nil
    or not validDateTime(year, month, day, hour, minute, 0)
  then
    return nil, "invalid"
  end

  local epoch = localEpoch(year, month, day, hour, minute, 0)
  if epoch == nil then
    return nil, "invalid"
  end
  now = if type(now) == "number" then now else os.time()
  if epoch <= now then
    return nil, "past"
  end
  return epoch, nil
end

function Reminder.localLabel(epoch)
  if type(epoch) ~= "number" then
    return ""
  end
  return os.date("%Y-%m-%d %H:%M", epoch)
end

return Reminder
