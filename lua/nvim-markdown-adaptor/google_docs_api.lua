local M = {
  client_id = "1061313657775-3tvcrig9qi4lhe0331pgmme8bsgj0pti.apps.googleusercontent.com",
  client_secrets_file = "/home/rick/.nvim-extension-client-secret.json", -- TODO: generalize
  redirect_uri = "http://localhost:9090/oauth2",
  auth_state = {}
}

local curl = require "plenary.curl"
local utils = require "nvim-markdown-adaptor.utils"
local settings = require "nvim-markdown-adaptor.settings"

local CWD = vim.fn.getcwd() .. "/lua/nvim-markdown-adaptor"
local SETTING_REFRESH_TOKEN = "google_api.refresh_token"

M.clear_and_seed_auth_state = function(this)
  -- Generates state and PKCE values.

  local code_verifier = vim.fn.rand()
  this.auth_state = {
    scope = "https://www.googleapis.com/auth/documents",
    redirect_uri = this.redirect_uri,
    state = "" .. vim.fn.rand(),
    code_verifier = code_verifier,
    code_challenge_method = "plain",
    code_challenge = code_verifier,
    -- todo: get SHA256 verifier to work... think there's a problem with base64 or the sha hashing
    -- code_challenge_method = "SHA256",
    -- code_challenge = encode_base64(vim.fn.sha256(code_verifier)):gsub("=", "") .. -- note: pkce doesn't want base64 padding https://www.rfc-editor.org/rfc/rfc7636#appendix-A
  }
end

M.load_secrets = function(this)
  utils.read_file(this.client_secrets_file, function(data)
    local secrets_data = vim.json.decode(data)
    this.client_secret = secrets_data.installed.client_secret
    this.client_id = secrets_data.installed.client_id
  end)
end

local function encode_base64(data)
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r;
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if (#x < 6) then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return b:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- exchanges an auth code for an auth token and refresh token
-- saves the auth token to memory
-- calls callback with the refresh token
M.exchange_code_for_token = function(this, params)
  assert(params.state == this.auth_state.state,
    ("Returned state <%s> does not match original state <%s>"):format(params.state, this.auth_state.state))

  local body = "code=" .. params.code ..
      "&client_id=" .. this.client_id ..
      "&client_secret=" .. this.client_secret ..
      "&redirect_uri=" .. this.auth_state.redirect_uri .. -- unclear what this needs to be
      "&code_verifier=" .. this.auth_state.code_verifier ..
      "&grant_type=authorization_code"

  curl.post("https://oauth2.googleapis.com/token", {
    raw_body = body,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    callback = function(response)
      if response.status ~= 200 then
        error("Unable to authorize against Google APIs")
        return
      end

      local result = vim.json.decode(response.body)
      assert(result.access_token, "No access_token found in the OAuth response")
      assert(result.refresh_token, "No refresh_token found in the OAuth response")
      assert(result.scope == this.auth_state.scope, "Unexpected auth scope: " .. result.scope)

      this.auth_state.access_token = result.access_token
      params.callback(result.refresh_token)
    end
  })
end

-- uses a refresh token to get a new auth token
-- saves the auth token to memory
-- the refresh token is multi-use
M.refresh_access_token = function(this, params)
  local body = "refresh_token=" .. params.refresh_token ..
      "&client_id=" .. this.client_id ..
      "&client_secret=" .. this.client_secret ..
      "&grant_type=refresh_token"

  curl.post("https://oauth2.googleapis.com/token", {
    raw_body = body,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    callback = function(response)
      if response.status ~= 200 then
        error("Unable to authorize against Google APIs")
        return
      end

      local result = vim.json.decode(response.body)
      assert(result.access_token, "No access_token found in the OAuth response")
      assert(result.scope == this.auth_state.scope, "Unexpected auth scope: " .. result.scope)

      this.auth_state.access_token = result.access_token
      if params.callback then
        params.callback()
      end
    end
  })
end


function M.get_authorization_url(this)
  local endpoint = "https://accounts.google.com/o/oauth2/v2/auth"

  local authorization_url = endpoint .. "?response_type=code" ..
      "&scope=" .. this.auth_state.scope ..
      "&redirect_uri=" .. this.auth_state.redirect_uri ..
      "&client_id=" .. this.client_id ..
      "&state=" .. this.auth_state.state ..
      "&code_challenge=" ..
      this.auth_state.code_challenge ..
      "&code_challenge_method=" .. this.auth_state.code_challenge_method

  return authorization_url
end

-- see also Google documentation
-- https://developers.google.com/identity/protocols/oauth2/native-app
--
-- Full flow...
-- check if we have access token
--  - true: return
--  - false: check if we have refresh token
--      - true:
--        - call exchange endpoint to get access token
--        - store access token in this session
--      - false:
--        - prepare url for oauth2 consent
--        - start http listener to listen to loopback call
--        - prompt user to open in browser
--        - on loopback call recieved
--          - store refresh token
--          - call exchange endpoint to get access token
--          - store access token in this session
--
M.oAuth2 = function(this, params)
  if not params.force_auth_flow then
    if this.auth_state.access_token ~= nil then
      params.callback()
      return
    end

    local refresh_token = settings.get(SETTING_REFRESH_TOKEN)
    if refresh_token ~= nil then
      this:refresh_access_token({ refresh_token = refresh_token, callback = params.callback })
      return
    end
  end

  -- todo: if we have a refresh token: exchange refresh token for access-token/refresh token pair
  -- todo: save access token in memory
  -- todo: store new refresh token
  -- todo: early return


  vim.ui.select({ "yes", "no" }, {
      prompt = "Google Docs access needs to be granted via browser. Continue?"
    },
    function(choice)
      if (choice ~= "yes") then
        return
      end

      print("Waiting for authorization to complete...")
      local url = M:get_authorization_url()
      vim.ui.open(url)

      -- listen for the response; this will currently block until the listener process ends (not great)
      local output = vim.fn.system("lua " .. CWD .. "/oauth2_listener.lua")
      local response = {}
      for c, s in output:gmatch("success,(.+),(.+)\n") do
        response.code = c
        response.state = s
      end

      M:exchange_code_for_token({
        code = response.code,
        state = response.state,
        callback = function(refresh_token)
          print("Google authorization successful")
          settings.set(SETTING_REFRESH_TOKEN, refresh_token)
          params.callback()
        end
      })
    end
  )
end

-- fetches a google doc
M.get = function(this, params)
  -- todo: output user function to run to auth
  assert(this.auth_state.access_token, "Not authorized to make google calls")
  local url = "https://docs.googleapis.com/v1/documents/" .. params.documentId

  local on_response = vim.schedule_wrap(function(response)
    local body = vim.json.decode(response.body)
    params.callback(body)
  end)

  curl.get(url, {
    headers = {
      ["Authorization"] = "Bearer " .. this.auth_state.access_token
    },
    callback = on_response
  })
end

M.batch_update = function(this, params)
  -- todo: output user function to run to auth
  assert(this.auth_state.access_token, "Not authorized to make google calls")
  local url = "https://docs.googleapis.com/v1/documents/" .. params.document_id .. ":batchUpdate"

  local on_response = vim.schedule_wrap(function(response)
    print(vim.json.encode(response))
    local body = vim.json.decode(response.body)

    if params.callback then
      params.callback(body)
    end
  end)

  local update_request_body = {
    requests = params.requests
  }
  print(vim.json.encode(update_request_body))
  curl.post(url, {
    headers = {
      ["Authorization"] = "Bearer " .. this.auth_state.access_token,
      ["Content-Type"] = "application/json",
    },
    raw_body = vim.json.encode(update_request_body),
    callback = on_response
  })
end


-- ordering matters
M:clear_and_seed_auth_state()
M:load_secrets()

return M
