local M = {}

local utils = require 'nvim-markdown-adaptor.utils'

local FRONTMATTER_GOOGLE_DOC_ID_KEY = 'google-doc-id'

--- @param msg string
---@return {[integer]: Element}
local function wrapped_error_command(msg)
  return { { type = "error", message = msg } }
end

local function get_root_node()
  local node = vim.treesitter.get_node({ pos = { 0, 0 } })

  while (node ~= nil and node:parent() ~= nil) do
    node = node:parent()
  end

  return node
end


--- @enum ElementType
local ELEMENT_TYPES = {
  heading = "heading",
  paragraph = "paragraph",
  list = "list",
  code = "code",
}
M.ELEMENT_TYPES = ELEMENT_TYPES

--- @class Element
--- @field type ElementType

--- Recursively parses TreeSitter tree into commands
---
---@param node TSNode
---@return {[integer]: Element}
local function parse_node(node, context)
  local type = node:type()

  local ctx = {}
  if not context then
    ctx.indent = 0
  else
    ctx = context
  end

  if (type == 'document' or type == 'section' or type == 'stream') then
    local commands = {}
    local child_iter = node:iter_children()
    local child = child_iter()
    while child ~= nil do
      local new_commands = parse_node(child, ctx)
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
        return wrapped_error_command("unkown heading marker " .. marker)
      end

      local heading_command = {
        type = ELEMENT_TYPES.heading,
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
        type = ELEMENT_TYPES.paragraph,
        content = vim.treesitter.get_node_text(content, 0),
        indent = ctx.indent,
        checked = ctx.checked
      }

      return { paragraph_command }
    else
      return { "empty" }
    end
  end

  if (type == 'list') then
    local next_list_item = node:iter_children()
    local list_item = next_list_item()

    local markerType = list_item:child(0):type()
    local is_ordered = false
    if (markerType == 'list_marker_dot') then
      is_ordered = true
    end

    local commands = {}
    while list_item do
      local next_content = list_item:iter_children()
      local checked = nil

      local content = next_content()
      while content do
        if content:type() == "task_list_marker_checked" then
          checked = true
        end

        if content:type() == "task_list_marker_unchecked" then
          checked = false
        end


        local new_context = { checked = checked }
        for k, v in pairs(ctx) do
          new_context[k] = v
        end

        if content:type() == "list" then
          new_context.indent = new_context.indent + 1
        end

        local newCommands = parse_node(content, new_context)
        utils.insert_all(commands, newCommands)

        content = next_content()
      end

      list_item = next_list_item()
    end

    local list_command = {
      type = ELEMENT_TYPES.list,
      indent = ctx.indent,
      is_ordered = is_ordered,
      items = commands
    }
    return { list_command }
  end

  if (type == 'fenced_code_block') then
    local next_content = node:iter_children()

    local program_command = {
      type = ELEMENT_TYPES.code,
    }

    local content_item = next_content()
    while content_item do
      if content_item:type() == 'code_fence_content' then
        program_command.content = vim.treesitter.get_node_text(content_item, 0)
      end

      if content_item:type() == 'info_string' then
        local next_info = content_item:iter_children()
        local info_item = next_info()
        while info_item do
          if info_item:type() == 'language' then
            program_command.language = vim.treesitter.get_node_text(info_item, 0)
          end
          info_item = next_info()
        end
      end

      content_item = next_content()
    end

    return { program_command }
  end

  return wrapped_error_command("unknown node type " .. type)
end

M.parse_current_buffer = function()
  local root_node = get_root_node()
  if root_node ~= nil then
    return parse_node(root_node)
  end
  return {}
end

return M
