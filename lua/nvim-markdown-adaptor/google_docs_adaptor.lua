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
    utils.insert_all(requests, {
      { deleteContentRange = { range = document_range } },
      { deleteParagraphBullets = { range = { startIndex = 1, endIndex = 1 } } },
    })
  end
  utils.insert_all(requests, update_requests)

  gapi:batch_update({ requests = requests, document_id = document.documentId })
end

local function to_gdocs_update_requests(commands, opts)
  local requests = {}
  local tabs = 0 -- see handling of list commands to see how this is used

  local index = 1
  if opts and opts.index then
    index = opts.index
  end

  for _, command in pairs(commands) do
    if command.type == "paragraph" then
      local text = ""
      for _ = 1, command.indent, 1 do
        text = text .. "\t"
      end
      text = text .. command.content .. "\n"
      tabs = tabs + command.indent

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

    if command.type == "list" then
      local list_items, nested_context = to_gdocs_update_requests(command.items, { index = index })
      utils.insert_all(requests, list_items)


      local bulletPreset = "BULLET_DISC_CIRCLE_SQUARE"
      if command.is_ordered then
        bulletPreset = "NUMBERED_DECIMAL_ALPHA_ROMAN"
      end

      if command.indent == 0 then
        table.insert(requests, {
          createParagraphBullets = {
            range = {
              startIndex = index,
              endIndex = nested_context.index
            },
            bulletPreset = bulletPreset
          }
        })

        -- tabs get removed when creating bullets; this number needs to be used to amend the index
        -- https://developers.google.com/docs/api/reference/rest/v1/documents/request#createparagraphbulletsrequest
        index = nested_context.index - nested_context.tabs
      else
        tabs = tabs + nested_context.tabs
        index = nested_context.index
      end
    end
  end


  local nested_context = { index = index, tabs = tabs }
  return requests, nested_context
end

local function update_gdoc()
  local elements = parser.parse_current_buffer()
  local update_requests = to_gdocs_update_requests(elements)
  print(vim.json.encode(update_requests))
  if #update_requests == 0 then
    print("No content. Stopping.")
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
end

return M
