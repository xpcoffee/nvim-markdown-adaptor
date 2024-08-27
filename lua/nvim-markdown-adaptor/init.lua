local adaptor = require('nvim-markdown-adaptor.google_docs_adaptor')
local gapi = require('nvim-markdown-adaptor.google_docs_api')
local options = require('nvim-markdown-adaptor.options')
local plugin_data = require('nvim-markdown-adaptor.plugin_data')

local M = {}

function M.setup(opts)
  options.init(opts)
  local data_file_path = options.get("data_file_path")
  if data_file_path then
    plugin_data.init(data_file_path)
  end
end

M.sync_to_google_doc = adaptor.sync_to_google_doc

M.reauthorize_google_api = function()
  gapi:oAuth2({ force_auth_flow = true })
end

return M
