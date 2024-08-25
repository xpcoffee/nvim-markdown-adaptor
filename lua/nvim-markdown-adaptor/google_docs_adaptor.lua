local M = {}

local gapi = require "nvim-markdown-adaptor.google_docs_api"
local parser = require "nvim-markdown-adaptor.parser"
local utils = require "nvim-markdown-adaptor.utils"

--- @param document table
--- @param update_requests table
local function replace_gdoc_contents(document, update_requests)
  local elements = document.body.content
  local document_range = {
    startIndex = 1,
    endIndex = elements[#elements].endIndex - 1 -- not the newline character at the end
  }

  local requests = {}

  if (document_range.endIndex > 2) then
    table.insert(requests, {
      deleteContentRange = {
        range = document_range
      }
    })
  end
  utils.insert_all(requests, update_requests)

  gapi:batch_update({ requests = requests, document_id = document.documentId })
end

local function to_gdocs_update_requests(commands)
  local requests = {}
  local index = 1

  for _, command in pairs(commands) do
    if command.type == "paragraph" then
      local text = command.content .. "\n"
      table.insert(requests, {
        insertText = {
          text = text,
          location = {
            index = index
          }
        }
      })

      index = index + #text
    end

    if command.type == "heading" then
      local text = command.content .. "\n"

      table.insert(requests, {
        insertText = {
          text = text,
          location = {
            index = index
          }
        }
      })

      local startIndex = index
      local endIndex = index + #text - 1
      table.insert(requests, {
        updateParagraphStyle = {
          range = {
            startIndex = startIndex,
            endIndex = endIndex
          },
          paragraphStyle = {
            namedStyleType = "HEADING_" .. command.level
          },
          fields = "namedStyleType"
        }
      })

      index = index + #text
    end

    if command.type == "code" then
      local text = command.content .. "\n"

      table.insert(requests, {
        insertText = {
          text = text,
          location = {
            index = index
          }
        }
      })

      local startIndex = index
      local endIndex = index + #text - 1
      table.insert(requests, {
        updateTextStyle = {
          range = {
            startIndex = startIndex,
            endIndex = endIndex
          },
          textStyle = {
            weightedFontFamily = {
              fontFamily = "Ubuntu Mono"
            }
          },
          fields = "weightedFontFamily"
        }
      })

      index = index + #text
    end
  end

  return requests
end

local function update_gdoc()
  local elements = parser.parse_current_buffer()
  local update_requests = to_gdocs_update_requests(elements)
  if #update_requests == 0 then
    print("Empty requests. Stopping.")
    return
  end

  -- update google docs
  local docId = "1MlkhxLgUxsol_zN6Irhy6jhcPSPZLKulBMV-YPSU6Bg"

  gapi:oAuth2({ -- currently broken: need to finish auth
    callback = function()
      gapi:get({
        documentId = docId,
        callback = function(doc) replace_gdoc_contents(doc, update_requests) end
      })
    end
  })
end

M.adapt_current_buffer = function()
  update_gdoc()
  -- vim.schedule_wrap(update_gdoc)()
end

return M
