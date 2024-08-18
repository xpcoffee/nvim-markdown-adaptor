local M = {}

-- WIP: This is about having a callback server that can get back the result of the authZ request
-- I currently have NO idea how to make this work...

-- for pegasus, install it manually using luarocks install pegasus
local Pegasus = require 'pegasus'
local Router = require 'pegasus.plugins.router'

local function start_server()
  local routes = {
    ["/stop"] = function(req, res)
      local stop = true
      return stop
    end,
    ["/hello"] = function(req, res)
      local stop = false
      print("hello!")
      return stop
    end,
  }
  local server = Pegasus:new({
    port = '9090',
    location = 'example/root',
    router = Router:new({ routes = routes })
  })
  server:start(function(request, response)
    local stop = false
    return stop
  end)
end

M.start_server = function()
  local async = require("plenary.async")
  local future = async.wrap(start_server, 0)
  async.run(start_server, function() print("done") end)()
end

return M
