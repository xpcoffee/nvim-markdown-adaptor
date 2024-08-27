--- Persists data for the plugin.
--- If configured with a data_file_path, that data will be written to the file and read on init.
--- (Maybe there's a more vim-native way to do this???)
---
--- @class PluginData
local M = {}

--- @type string | nil
local data_file_path = nil

--- @type { [string]: string }
local data = {}

local utils = require "nvim-markdown-adaptor.utils"

--- @param name string
M.get = function(name)
  return data[name]
end

---@param callback fun(settings: { [string]: string }) | nil
M.load_from_file = function(callback)
  if not data_file_path then
    return
  end

  utils.read_file(data_file_path, function(file_data)
    if not file_data or file_data == "" then
      data = {}
      if callback then
        callback({})
      end
      return
    end

    data = vim.json.decode(file_data)
    if callback then
      callback(data)
    end
  end)
end

--- @param name string
--- @param value string
local function set_in_memory(name, value)
  data[name] = value
end

--- @param callback fun() | nil
local function write_to_file(callback)
  if data_file_path then
    utils.write_file(data_file_path, vim.json.encode(data), callback)
  end
end

--- @param name string
--- @param value string
--- @param callback fun() | nil
M.set = function(name, value, callback)
  set_in_memory(name, value)
  write_to_file(callback)
end


--- @param data_file string
---@param callback fun(settings: { [string]: string }) | nil
M.init = function(data_file, callback)
  data_file_path = data_file
  M.load_from_file(callback)
end

return M
