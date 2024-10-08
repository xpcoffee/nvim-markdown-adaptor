--- @class GoogleDocsApi
--- @field client_id string
--- @field client_secret string
--- @field redirect_uri string
--- @field auth_state AuthState | nil
M = {}

--- @class AuthState
--- @field scope string | nil
--- @field state string | nil
--- @field code_verifier string | nil
--- @field code_challenge string | nil
--- @field code_challenge_method string | nil
--- @field access_token string | nil

local curl = require "plenary.curl"
local utils = require "nvim-markdown-adaptor.utils"
local options = require "nvim-markdown-adaptor.options"
local plugin_data = require "nvim-markdown-adaptor.plugin_data"

local CWD = vim.fn.getcwd() .. "/lua/nvim-markdown-adaptor"
local SETTING_REFRESH_TOKEN = "__google_api.refresh_token"

---@param this GoogleDocsApi
---@param callback fun() | nil
M.init = function(this, callback)
  local redirect_uri_port = options.get("google_oauth_redirect_port")
  assert(redirect_uri_port, "Empty value for redirect_uri_port")

  this.redirect_uri = "http://localhost:" .. redirect_uri_port .. "/oauth2" -- FIXME: assign port to the server

  local code_verifier = "" .. vim.fn.rand()
  this.auth_state = {
    scope = "https://www.googleapis.com/auth/documents",
    state = "" .. vim.fn.rand(),
    code_verifier = code_verifier,
    code_challenge_method = "plain",
    code_challenge = code_verifier,
  }

  this:load_secrets(callback)
end

---@param this GoogleDocsApi
---@param callback fun() | nil
M.load_secrets = function(this, callback)
  local client_secrets_file = options.get(options.OPTION.google_client_file)
  assert(client_secrets_file, "Empty value for client_secrets_file")

  utils.read_file(client_secrets_file, function(data)
    assert(data, "No secret data returned when reading client file")

    local secrets_data = vim.json.decode(data)
    assert(secrets_data.installed and secrets_data.installed.client_secret, "No client_secret found in client file")
    assert(secrets_data.installed and secrets_data.installed.client_secret, "No client_id found in client file")

    this.client_secret = secrets_data.installed.client_secret
    this.client_id = secrets_data.installed.client_id

    if callback then
      callback()
    end
  end)
end

--- exchanges an auth code for an auth token and refresh token
--- saves the auth token to memory
--- calls callback with the refresh token
---
--- @param this GoogleDocsApi
M.exchange_code_for_token = function(this, params)
  assert(this.auth_state, "GoogleDocsApi not initialized. See setup()")
  assert(params.state == this.auth_state.state,
    ("Returned state <%s> does not match original state <%s>"):format(params.state, this.auth_state.state))

  local body = "code=" .. params.code ..
      "&client_id=" .. this.client_id ..
      "&client_secret=" .. this.client_secret ..
      "&redirect_uri=" .. this.redirect_uri .. -- unclear what this needs to be
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
  assert(this.auth_state, "GoogleDocsApi not initialized. See setup()")
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


--- @return string
function M.get_authorization_url(this)
  assert(this.auth_state, "GoogleDocsApi not initialized. See setup()")
  local endpoint = "https://accounts.google.com/o/oauth2/v2/auth"

  local authorization_url = endpoint .. "?response_type=code" ..
      "&scope=" .. this.auth_state.scope ..
      "&redirect_uri=" .. this.redirect_uri ..
      "&client_id=" .. this.client_id ..
      "&state=" .. this.auth_state.state ..
      "&code_challenge=" ..
      this.auth_state.code_challenge ..
      "&code_challenge_method=" .. this.auth_state.code_challenge_method

  return authorization_url
end

--- @class OAuthParams
--- @field force_auth_flow boolean | nil - bypasses cached credentials
--- @field callback fun() | nil - called if the flow succeeds

--- Performs Oauth2 flow for Google Docs API
---
--- see also Google documentation
--- https://developers.google.com/identity/protocols/oauth2/native-app
--
--- Full flow...
--- check if we have access token
---  - true: return
---  - false: check if we have refresh token
---      - true:
---        - call exchange endpoint to get access token
---        - store access token in this session
---      - false:
---        - prepare url for oauth2 consent
---        - start http listener to listen to loopback call
---        - prompt user to open in browser
---        - on loopback call recieved
---          - store refresh token
---          - call exchange endpoint to get access token
---          - store access token in this session
---
--- @param this GoogleDocsApi
--- @param params OAuthParams
M.oAuth2 = function(this, params)
  if not this.auth_state then
    this:init(function()
      this:oAuth2(params)
    end)
    return
  end

  if not params.force_auth_flow then
    if this.auth_state.access_token ~= nil then
      params.callback()
      return
    end

    local refresh_token = plugin_data.get(SETTING_REFRESH_TOKEN)
    if refresh_token ~= nil then
      this:refresh_access_token({ refresh_token = refresh_token, callback = params.callback })
      return
    end
  end

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
          plugin_data.set(SETTING_REFRESH_TOKEN, refresh_token)
          if params and params.callback then
            params.callback()
          end
        end
      })
    end
  )
end



--- @class GetParams
--- @field document_id string - the Google Doc ID
--- @field callback fun(obj) - called with document content, if the document could be fetched

--- Fetches the content of a Google Doc
---
--- @param this GoogleDocsApi
--- @param params GetParams
M.get = function(this, params)
  assert(this.auth_state and this.auth_state.access_token,
    "Not authorized to make google calls. See reauthorize_google_api()")
  local url = "https://docs.googleapis.com/v1/documents/" .. params.document_id

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

--- @class BatchUpdateParams
--- @field document_id string - the Google Doc ID
--- @field requests table[] - the Google Doc ID
--- @field callback fun(object) | nil  called with the response content

--- Fetches the content of a Google Doc
---
--- @param this GoogleDocsApi
--- @param params BatchUpdateParams
M.batch_update = function(this, params)
  assert(this.auth_state and this.auth_state.access_token,
    "Not authorized to make google calls. See reauthorize_google_api()")
  local url = "https://docs.googleapis.com/v1/documents/" .. params.document_id .. ":batchUpdate"

  local on_response = vim.schedule_wrap(function(response)
    if response.status ~= 200 then
      error(vim.json.encode(response))
      return
    end

    local body = vim.json.decode(response.body)

    if params.callback then
      params.callback(body)
    end
  end)

  local update_request_body = {
    requests = params.requests
  }
  curl.post(url, {
    headers = {
      ["Authorization"] = "Bearer " .. this.auth_state.access_token,
      ["Content-Type"] = "application/json",
    },
    raw_body = vim.json.encode(update_request_body),
    callback = on_response
  })
end


return M
