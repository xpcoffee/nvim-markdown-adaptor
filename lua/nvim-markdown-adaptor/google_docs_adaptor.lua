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

  gapi:batch_update({
    requests = requests,
    document_id = document.documentId,
    callback = function()
      print("Markdown synced to https://docs.google.com/document/d/" .. document.documentId)
    end
  })
end

local function to_gdocs_update_requests(elements, opts)
  local requests = {}
  local tabs = 0 -- see handling of list commands to see how this is used

  local index = 1
  if opts and opts.index then
    index = opts.index
  end

  for _, element in pairs(elements) do
    if element.type == parser.ELEMENT_TYPES.paragraph then
      local text = ""
      for _ = 1, element.indent, 1 do
        text = text .. "\t"
      end
      text = text .. element.content .. "\n"
      tabs = tabs + element.indent

      table.insert(requests, {
        insertText = {
          text = text,
          location = {
            index = index
          }
        }
      })

      if element.checked then
        table.insert(requests, {
          updateTextStyle = {
            range = {
              startIndex = index,
              endIndex = index + #text - 1
            },
            textStyle = {
              strikethrough = element.checked
            },
            fields = "strikethrough"
          }
        })
      end

      index = index + #text
    end

    if element.type == parser.ELEMENT_TYPES.heading then
      local text = element.content .. "\n"

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
            namedStyleType = "HEADING_" .. element.level
          },
          fields = "namedStyleType"
        }
      })

      index = index + #text
    end

    if element.type == parser.ELEMENT_TYPES.code then
      local text = element.content .. "\n"

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

    if element.type == parser.ELEMENT_TYPES.list then
      local list_items, nested_context = to_gdocs_update_requests(element.items, { index = index })
      utils.insert_all(requests, list_items)


      local bulletPreset = "BULLET_DISC_CIRCLE_SQUARE"
      if element.is_ordered then
        bulletPreset = "NUMBERED_DECIMAL_ALPHA_ROMAN"
      end

      if element.indent == 0 then
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


--- @class GoogleDocSyncParams
--- @field document_id string

--- @param params GoogleDocSyncParams
M.sync_to_google_doc = function(params)
  local elements = parser.parse_current_buffer()
  local update_requests = to_gdocs_update_requests(elements)
  if #update_requests == 0 then
    print("No content. Stopping.")
    return
  end

  if not params.document_id then
    -- todo: try to fetch from document
    error("No document ID provided to sync_to_google_doc")
  end

  gapi:oAuth2({
    callback = function()
      gapi:get({
        document_id = params.document_id,
        callback = function(doc) replace_gdoc_contents(doc, update_requests) end
      })
    end
  })
end

return M
