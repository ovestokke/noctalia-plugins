--!nonstrict

local Space = {}

function Space.accessible(space)
  return type(space) == "table"
    and type(space.name) == "string"
    and string.match(space.name, "^spaces/[%w-]+$") ~= nil
    and (space.currentUserRole == "ADMIN" or space.currentUserRole == "USER")
end

function Space.contains(spaces, name)
  if name == "" then return true end
  for _, space in ipairs(spaces) do
    if space.name == name then return true end
  end
  return false
end

function Space.filter(userName, name)
  if name ~= "" then
    return 'space == ' .. noctalia.json.encode(name)
  end
  return 'creator == ' .. noctalia.json.encode(userName) .. ' && space == null'
end

function Space.destination(memo, name)
  memo.visibility = "PRIVATE"
  if name ~= "" then
    memo.space = name
    memo.visibility = "SPACE"
  end
end

return Space
