local M = {}

local gapi = require "nvim-markdown-adaptor.google_docs_api"
local parser = require "nvim-markdown-adaptor.parser"
local utils = require "nvim-markdown-adaptor.utils"

--- @param document table
--- @param update_requests table
local function replace_gdoc_contents(document, update_requests)
  local elements = document.body.content
  local document_range = {
    startIndex = 0,
    endIndex = elements[#elements].endIndex
  }

  local requests = {
    deleteContentRange = {
      range = document_range
    }
  }

  utils.insert_all(requests, update_requests)

  local batch_update_request = vim.json.encode({
    documentId = document.id,
    requests = requests,
  })

  print(batch_update_request)
end

local function to_gdocs_update_requests(commands)
  print(vim.json.encode(commands))
  return {}
end

local function update_gdoc()
  local elements = parser.parse_current_buffer()
  local update_requests = to_gdocs_update_requests(elements)
  -- if #update_requests == 0 then
  --   print("Empty requests. Stopping.")
  --   return
  -- end

  -- update google docs
  local docId = "1MlkhxLgUxsol_zN6Irhy6jhcPSPZLKulBMV-YPSU6Bg"

  gapi:oAuth2({ -- currently broken: need to finish auth
    callback = gapi:get({
      documentId = docId,
      callback = function(doc) replace_gdoc_contents(doc, update_requests) end
    })
  })
end

M.adapt_current_buffer = function()
  gapi:prepare_authorization_url() -- calls vimscripts, which needs to be done in main thread
  update_gdoc()
  -- vim.schedule_wrap(update_gdoc)()
end

return M
