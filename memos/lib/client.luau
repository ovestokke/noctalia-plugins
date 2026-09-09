--!nonstrict

local Client = {}

local function isLoopbackHttp(url)
  local authority = string.match(url, "^http://([^/]+)")
  if authority == nil then
    return false
  end
  return authority == "localhost"
    or string.match(authority, "^localhost:%d+$") ~= nil
    or authority == "127.0.0.1"
    or string.match(authority, "^127%.0%.0%.1:%d+$") ~= nil
    or authority == "[::1]"
    or string.match(authority, "^%[::1%]:%d+$") ~= nil
end

local function normalizeBaseUrl(value)
  if type(value) ~= "string" then
    return nil, "invalid_url"
  end

  local url = noctalia.string.trim(value)
  url = string.gsub(url, "/+$", "")
  if url == "" then
    return nil, "unconfigured"
  end
  if string.find(url, "%s") ~= nil or string.find(url, "[?#]") ~= nil then
    return nil, "invalid_url"
  end
  if string.match(url, "^https://[^/]+@") ~= nil or string.match(url, "^http://[^/]+@") ~= nil then
    return nil, "invalid_url"
  end
  if string.match(url, "^https://[^/]+") == nil and not isLoopbackHttp(url) then
    return nil, "invalid_url"
  end

  return url, nil
end

function Client.managedTokenPath()
  local directory = noctalia.pluginDataDir()
  if type(directory) ~= "string" or directory == "" then
    return nil
  end
  return directory .. "/token"
end

local function readToken(path, missingError)
  local token = noctalia.readFile(path)
  if type(token) ~= "string" then
    return nil, missingError
  end
  token = noctalia.string.trim(token)
  if token == "" then
    return nil, "token_empty"
  end
  return token, nil
end

function Client.load()
  local baseUrl, urlError = normalizeBaseUrl(noctalia.getConfig("instance_url"))
  if baseUrl == nil then
    return nil, urlError
  end

  local tokenPath = noctalia.getConfig("token_file")
  local token
  local tokenError
  if type(tokenPath) == "string" and noctalia.string.trim(tokenPath) ~= "" then
    token, tokenError = readToken(noctalia.string.trim(tokenPath), "token_file_unreadable")
  else
    local managedPath = Client.managedTokenPath()
    if managedPath == nil then
      return nil, "token_storage_unavailable"
    end
    token, tokenError = readToken(managedPath, "token_missing")
  end
  if token == nil then
    return nil, tokenError
  end

  return {
    baseUrl = baseUrl,
    token = token,
  }, nil
end

local function requestHeaders(client, hasBody, stream)
  local headers = {
    if stream then "Accept: text/event-stream" else "Accept: application/json",
    "Authorization: Bearer " .. client.token,
  }
  if hasBody then
    table.insert(headers, "Content-Type: application/json")
  end
  return headers
end

function Client.request(client, method, path, body, onDone)
  return noctalia.http({
    url = client.baseUrl .. path,
    method = method,
    body = body,
    headers = requestHeaders(client, body ~= nil, false),
  }, onDone)
end

function Client.stream(client, path, onLine, onClose)
  return noctalia.httpStream({
    url = client.baseUrl .. path,
    method = "GET",
    headers = requestHeaders(client, false, true),
  }, onLine, onClose)
end

function Client.decodeObject(body)
  if type(body) ~= "string" or body == "" then
    return nil, "invalid_json"
  end
  local value = noctalia.json.decode(body)
  if type(value) ~= "table" then
    return nil, "invalid_json"
  end
  return value, nil
end

function Client.statusError(response)
  if type(response) ~= "table" or response.ok ~= true then
    return "network_error"
  end
  if response.status == 401 then
    return "unauthorized"
  end
  if response.status == 403 then
    return "forbidden"
  end
  if response.status < 200 or response.status >= 300 then
    return "server_error"
  end
  return nil
end

return Client
