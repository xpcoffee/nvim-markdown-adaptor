local M = {
  api_key = "nope",
  client_id = "1061313657775-3tvcrig9qi4lhe0331pgmme8bsgj0pti.apps.googleusercontent.com",
  client_secrets_file = "/home/rick/.nvim-extension-client-secret.json" -- TODO: generalize
}

local curl = require "plenary.curl"
local utils = require "nvim-markdown-adaptor.utils"

M.load_secrets = function(this, params)
  utils.read_file(this.client_secrets_file, function(data)
    local secretsData = vim.json.decode(data)
    this.clientSecret = secretsData.installed.client_secret
    this.client_id = secretsData.installed.client_id
    params.callback()
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

M.prepare_authorization_url = function(this)
  -- Generates state and PKCE values.
  local state = vim.fn.rand();
  local codeVerifier = vim.fn.rand();
  local codeChallenge = encode_base64(vim.fn.sha256(codeVerifier));
  local codeChallengeMethod = "S256";
  local endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
  local redirect_uri = "http://localhost:9090/hello"

  this.authorization_url = endpoint .. "?response_type=code" ..
      "&scope=openid%20profile" ..
      "&redirect_uri=" .. redirect_uri .. -- should be local running server.. how to do this?
      "&client_id=" .. this.client_id ..
      "&state=" .. state ..
      "&code_challenge=" ..
      codeChallenge:gsub("=", "") .. -- note: pkce doesn't want base64 padding https://www.rfc-editor.org/rfc/rfc7636#appendix-A
      "&code_challenge_method=" .. codeChallengeMethod
end


function M.get_authorization_url(this)
  return this.authorization_url
end

M.oAuth2 = function(this, params)
  print("Authorizing access to Google Docs...")


  M:load_secrets({
    callback = function()
      print("Auth url: " .. M:get_authorization_url())
      vim.ui.select({ "yes", "no" }, {
          prompt = "Need to authorize in brower. Continue?"
        },
        function()
          local url = M:get_authorization_url()
          vim.ui.open(url)
        end
      )

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

      print("Google authorization successful")
      params.callback()
    end
  })
end

M.get = function(this, params)
  print("fetching details for " .. params.documentId)
  local url = ("https://docs.googleapis.com/v1/documents/" ..
    params.documentId .. "?key=" .. this.api_key)

  --- FIXME: currently failing  with 401 here
  local on_response = vim.schedule_wrap(function(response)
    print(vim.json.encode(response))
    local body = vim.json.decode(response.body)
    params.callback(body)
  end)

  curl.get(url, { callback = on_response })
end
return M
