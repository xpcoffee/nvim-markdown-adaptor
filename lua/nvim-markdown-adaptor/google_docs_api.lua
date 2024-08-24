local M = {
  api_key = "nope",
  client_id = "1061313657775-3tvcrig9qi4lhe0331pgmme8bsgj0pti.apps.googleusercontent.com",
  client_secrets_file = "/home/rick/.nvim-extension-client-secret.json", -- TODO: generalize
  redirect_uri = "http://localhost:9090/oauth2"
}

local curl = require "plenary.curl"
local utils = require "nvim-markdown-adaptor.utils"

local CWD = vim.fn.getcwd() .. "/lua/nvim-markdown-adaptor"

M.load_secrets = function(this)
  utils.read_file(this.client_secrets_file, function(data)
    local secrets_data = vim.json.decode(data)
    this.client_secret = secrets_data.installed.client_secret
    this.client_id = secrets_data.installed.client_id
  end)
end
M:load_secrets()

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

M.seed_auth_state = function(this)
  -- Generates state and PKCE values.

  local code_verifier = vim.fn.rand()
  this.auth_state = {
    scope = "https://www.googleapis.com/auth/documents",
    redirect_uri = this.redirect_uri,
    state = "" .. vim.fn.rand(),
    code_verifier = code_verifier,
    code_challenge = encode_base64(vim.fn.sha256(code_verifier))
  }
end

M.exchange_code_for_token = function(this, params)
  print(vim.json.encode({ now = params.state, orig = this.auth_state.state }))
  assert(params.state == this.auth_state.state,
    ("Returned state <%s> does not match original state <%s>"):format(params.state, this.auth_state.state))

  local body = string.format(
    "code=%s&redirect_uri=%s&client_id=%s&client_secret=%s&code_verifier=%s&scope=%s&grant_type=authorization_code",
    params.code,
    this.auth_state.redirect_uri,
    this.client_id,
    this.client_secret,
    this.auth_state.code_verifier,
    this.auth_state.scope
  )

  -- fixeme: currently failing with invalid code verifier
  print("exchange body " .. body)


  curl.post("https://www.googleapis.com/oauth2/v4/token", {
    raw_body = body,
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Accept"] = "Accept=text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    },
    callback = function(response)
      print("exchange response")
      print(vim.json.encode(response))
    end
  })

  -- string tokenRequestBody = string.Format("code={0}&redirect_uri={1}&client_id={2}&code_verifier={3}&client_secret={4}&scope=&grant_type=authorization_code",
  --     code,
  --     Uri.EscapeDataString(redirectUri),
  --     clientId,
  --     codeVerifier,
  --     clientSecret
  --     );
  --
  -- // sends the request
  -- HttpWebRequest tokenRequest = (HttpWebRequest)WebRequest.Create(tokenRequestUri);
  -- tokenRequest.Method = "POST";
  -- tokenRequest.ContentType =="application/x-www-form-urlencoded";
  -- tokenRequest.Accept = "Accept=text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";
end


function M.get_authorization_url(this)
  local codeChallengeMethod = "S256";
  local endpoint = "https://accounts.google.com/o/oauth2/v2/auth"

  local authorization_url = endpoint .. "?response_type=code" ..
      "&scope=" .. this.auth_state.scope ..
      "&redirect_uri=" .. this.auth_state.redirect_uri ..
      "&client_id=" .. this.client_id ..
      "&state=" .. this.auth_state.state ..
      "&code_challenge=" ..
      this.auth_state.code_challenge:gsub("=", "") .. -- note: pkce doesn't want base64 padding https://www.rfc-editor.org/rfc/rfc7636#appendix-A
      "&code_challenge_method=" .. codeChallengeMethod

  return authorization_url
end

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
  -- todo: fetch refresh token from store if we have one
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
      print(vim.json.encode(response))

      M:exchange_code_for_token({
        code = response.code,
        state = response.state
      })

      -- todo: save access token in memory
      -- todo: store new refresh token

      print("Google authorization successful")
      -- todo: uncomment once oauth is working
      -- params.callback()
    end
  )
end

-- fetches a google doc
M.get = function(this, params)
  print("fetching details for " .. params.documentId)
  local url = ("https://docs.googleapis.com/v1/documents/" ..
    params.documentId .. "?key=" .. this.api_key)

  local on_response = vim.schedule_wrap(function(response)
    print(vim.json.encode(response))
    local body = vim.json.decode(response.body)
    params.callback(body)
  end)

  curl.get(url, { callback = on_response })
end
return M
