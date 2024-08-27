--- Confugration for the plugin.
--- Stored in memory. See PluginData for persistence.
---
--- @class Options
local M = {}
local options = {}


--- @enum Option
local OPTION = {
  data_file_path = "data_file_path",
  google_client_file = "google_client_file_path",
  google_oauth_redirect_port = "google_oauth_redirect_port",
}
M.OPTION = OPTION

local defaults = {
  [OPTION.google_oauth_redirect_port] = "9090"
}

--- @param name Option
--- @return string | nil
M.get = function(name)
  return options[name]
end

--- @param name Option
--- @param value string
M.set = function(name, value)
  options[name] = value
end

--- @param opts { [Option]: string }
M.init = function(opts)
  for _, required_config in pairs({ OPTION.google_client_file }) do
    assert(opts[required_config], "Missing required config: " .. required_config)
  end

  for k, v in pairs(defaults) do
    M.set(k, v)
  end

  for _, option_key in pairs(OPTION) do
    local option_value = opts[option_key]
    if option_value then
      M.set(option_key, option_value)
    end
  end
end

return M
