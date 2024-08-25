local M = {}

local utils = require 'nvim-markdown-adaptor.utils'

local FRONTMATTER_GOOGLE_DOC_ID_KEY = 'google-doc-id'

local function get_error_command(msg)
  return { { type = "error", message = msg } }
end

local function get_root_node()
  local node = vim.treesitter.get_node({ pos = { 0, 0 } })

  while (node ~= nil and node:parent() ~= nil) do
    node = node:parent()
  end

  return node
end

--- Recursively parses TreeSitter tree into commands
---
---@param node TSNode
---@return table
local function parse_node(node)
  local type = node:type()

  if (type == 'document' or type == 'section' or type == 'stream') then
    local commands = {}
    local child_iter = node:iter_children()
    local child = child_iter()
    while child ~= nil do
      local new_commands = parse_node(child)
      utils.insert_all(commands, new_commands)
      child = child_iter()
    end
    return commands
  end

  if type == 'minus_metadata' then
    local map = node:child(0)

    local child_iter = node:iter_children()
    local child = child_iter()
    while child ~= nil do
      print("child " .. child:type())
    end

    while (map ~= nil and map:type() ~= 'block_mapping') do
      print("map chile type " .. map:type())
      map = map:child(0)
    end

    if map == nil then
      return {}
    end

    local pairs_iterator = map:iter_children()
    local pair = pairs_iterator()
    while (pair ~= nil) do
      local key = pair:child(0)
      local value = pair:child(1)
      if (key ~= nil and value ~= nil) then
        local key_text = vim.treesitter.get_node_text(key, 0)

        if (key_text == FRONTMATTER_GOOGLE_DOC_ID_KEY) then
          local frontmatter_command = {
            type = "frontmatter",
            google_doc_id = vim.treesitter.get_node_text(value, 0)
          }
          return { frontmatter_command }
        end
      end
    end
    return {}
  end

  if (type == 'atx_heading') then
    local marker = node:child(0):type()
    local content = node:child(1)
    local heading_lvl = 1
    if (content ~= nil) then
      if (marker ~= nil and marker == 'atx_h1_marker') then
        heading_lvl = 1
      elseif (marker ~= nil and marker == 'atx_h2_marker') then
        heading_lvl = 2
      elseif (marker ~= nil and marker == 'atx_h3_marker') then
        heading_lvl = 3
      elseif (marker ~= nil and marker == 'atx_h4_marker') then
        heading_lvl = 4
      else
        return get_error_command("unkown heading marker " .. marker)
      end

      local heading_command = {
        type = "heading",
        level = heading_lvl,
        content = vim.treesitter.get_node_text(content, 0)
      }
      return { heading_command }
    end

    return {}
  end


  if (type == 'paragraph') then
    local content = node:child(0)
    if (content ~= nil) then
      local paragraph_command = {
        type = "paragraph",
        content = vim.treesitter.get_node_text(content, 0)
      }
      return { paragraph_command }
    else
      return { "empty" }
    end
  end

  if (type == 'list') then
    local child_iter = node:iter_children()
    local list_item = child_iter()

    local markerType = list_item:child(0):type()
    local is_ordered = false
    if (markerType == 'list_marker_dot') then
      is_ordered = true
    end

    local commands = {}
    while list_item ~= nil do
      local list_item_content = list_item:child(1)
      if (list_item_content ~= nil) then
        local newCommands = parse_node(list_item_content)
        utils.insert_all(commands, newCommands)
      end
      list_item = child_iter()
    end

    local list_command = {
      type = "list",
      is_ordered = is_ordered,
      items = commands
    }
    return { list_command }
  end

  if (type == 'fenced_code_block') then
    local program = node:child(3)

    local language = "unknown"
    local info = node:child(1)
    if (info ~= nil) then
      local language_info = info:child(0)
      if (language_info ~= nil) then
        language = vim.treesitter.get_node_text(language_info, 0)
      end
    end

    if (program ~= nil) then
      local content = vim.treesitter.get_node_text(program, 0)
      local program_command = {
        type = "code",
        langauge = language,
        content = content
      }
      return { program_command }
    end
  end

  return get_error_command("unknown node type " .. type)
end

M.parse_current_buffer = function()
  local root_node = get_root_node()
  if root_node ~= nil then
    return parse_node(root_node)
  end
  return {}
end

return M
