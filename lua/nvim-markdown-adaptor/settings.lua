local M = { settings = {} }

local utils = require "nvim-markdown-adaptor.utils"
local plugin_settings_file = "/home/rick/.nvim-markdown-adaptor.json" -- todo: generalize

M.load_from_file = function(callback)
  utils.read_file(plugin_settings_file, function(data)
    if not data or data == "" then
      if callback then
        callback({})
      end
      return
    end

    local settings = vim.json.decode(data)
    M.settings = settings
    if callback then
      callback(settings)
    end
  end)
end

M.get = function(name)
  return M.settings[name]
end

M.set = function(name, value)
  local new_settings = {}
  for k, v in pairs(M.settings) do
    new_settings[k] = v
  end

  new_settings[name] = value

  utils.write_file(plugin_settings_file, vim.json.encode(new_settings), function()
    M.settings = new_settings
  end)
end

return M
