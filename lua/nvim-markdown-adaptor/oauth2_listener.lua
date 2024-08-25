#!/usr/bin/lua

-- todo: document in readme prerequisites
-- For now pegasus server needs to be installed manually using `luarocks install pegasus`
local Pegasus = require 'pegasus'
local Router = require 'pegasus.plugins.router'

local function start_server()
  local routes = {
    -- recieves the oauth2 callback and prints it to the command line
    -- the program that needs to auth is expected to read the result from stdout
    ["/oauth2"] = {
      GET = function(req, resp)
        local state = req.querystring.state
        local code = req.querystring.code

        local skipPostFunction = false

        if state == nil or code == nil then
          resp:statusCode(400):write("Both 'code' and 'state' query params are required."):close()
          skipPostFunction = true
        else
          print("success," .. code .. "," .. state) -- do not remove; this is listened to by the plugin
          resp:statusCode(200):write("OK"):close()
        end

        return skipPostFunction
      end,

      postFunction = function()
        os.exit(0)
      end
    },
    ["/stop"] = {
      DELETE = function(_, resp)
        resp:statusCode(202):write("Shutting down server"):close()
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

  server:start(function(_, _) end)
end

start_server()
