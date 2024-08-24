#!/usr/bin/lua

-- WIP: This is about having a callback server that can get back the result of the authZ request
-- I currently have NO idea how to make this work...

-- for pegasus, install it manually using luarocks install pegasus
local Pegasus = require 'pegasus'
local Router = require 'pegasus.plugins.router'

local function start_server()
  local state_map = {}

  local routes = {
    ["/oauth2"] = {
      GET = function(req, resp)
        local state = req.querystring.state
        local code = req.querystring.code
        state_map[state] = code

        resp:statusCode(200):close()
        os.exit(0)
      end
    },
    ["/stop"] = {
      DELETE = function(req, resp)
        resp:statusCode(202)
        resp:close()
        os.exit(0)
      end
    },
  }
  local server = Pegasus:new({
    port = '9090',
    plugins = {
      Router:new({ routes = routes })
    }
  })

  server:start(function(request, response)
    if request:method() == "DELETE" then
      print("should stop...")
    end
  end)
end

start_server()
