local M = {}

local utils = require 'nvim-markdown-adaptor.utils'

local FRONTMATTER_GOOGLE_DOC_ID_KEY = 'google-doc-id'

--- @param msg string
---@return {[integer]: Element}
local function wrapped_error_element(msg)
  return { { type = "error", message = msg } }
end

local function get_root_node()
  -- STUCK: parsing paragraphs e.g. for links/formatting
  -- trying to get markdown inline to be recognised... not working

  -- local node = vim.treesitter.get_node({ pos = { 0, 0 }, ignore_injections = false })
  local node = vim.treesitter.get_parser(0, "markdown", {
    injections = {
      markdown = '((inline) @injection.content (#set! injection.language "markdown_inline"))'
    }
  }):named_node_for_range({ 0, 0, 0, 0 })

  while node and node:parent() do
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
  link = "link",
}
M.ELEMENT_TYPES = ELEMENT_TYPES

--- @param node TSNode
--- @return {[integer]: Element}
local function parse_paragraph_contents(node, ctx)
  assert(not ctx.visited_ids[node:id()], "Node seen more than once. Content is being parsed multiple times.")
  ctx.visited_ids[node:id()] = true

  if not node:named() then
    return {}
  end

  local update_text_elements = {}

  if node:type() == "inline" then
    local inline_node = node;
    local next_content = inline_node:iter_children()
    local content = next_content()
    while content do
      local child_elements = parse_paragraph_contents(content, ctx)
      utils.insert_all(update_text_elements, child_elements)
      content = next_content()
    end


    if #update_text_elements == 0 then -- output full text if we couldn't find sub-content
      local text = vim.treesitter.get_node_text(inline_node, 0)
      local paragraph_element = {
        type = ELEMENT_TYPES.paragraph,
        content = text,
        indent = ctx.indent,
        checked = ctx.checked
      }

      table.insert(update_text_elements, paragraph_element)
    end
  end

  -- STUCK: parsing paragraphs e.g. for links/formatting
  -- this is not working...
  -- this doesn't seem to be populated in the parsed tree, although I can see them with InspectTree
  -- I have no idea how to get this content via treesitter....
  if node:type() == "inline_link" then
    local link_element = {
      type = ELEMENT_TYPES.link,
    }

    local next_content = node:iter_children()
    local content = next_content()
    while content do
      if content:type() == "link_text" then
        link_element.text = vim.treesitter.get_node_text(content, 0)
      end

      if content:type() == "link_destination" then
        link_element.url = vim.treesitter.get_node_text(content, 0)
      end
      content = next_content()
    end


    -- TODO replace with a real link element; currently just outputting text
    local dummy_link = {
      type = ELEMENT_TYPES.paragraph,
      content = link_element.text .. "-->" .. link_element.url,
      indent = ctx.indent,
      checked = ctx.checked
    }

    table.insert(update_text_elements, dummy_link)
  end

  return update_text_elements
end

--- @class Element
--- @field type ElementType

--- Recursively parses TreeSitter tree into elements
---
---@param node TSNode
---@return {[integer]: Element}
local function parse_node(node, context)
  if not node:named() then -- we only want to work with an AST
    return {}
  end

  local type = node:type()

  local ctx = { visited_ids = {} }
  if not context then
    ctx.indent = 0
  else
    ctx = context
  end

  if (type == 'document' or type == 'section' or type == 'stream') then
    local elements = {}
    local child_iter = node:iter_children()
    local child = child_iter()
    while child do
      local new_elements = parse_node(child, ctx)
      utils.insert_all(elements, new_elements)
      child = child_iter()
    end
    return elements
  end

  -- STUCK: parsing google doc ID from the frontmatter
  -- this is not working...
  -- this doesn't seem to be populated in the parsed tree, although I can see them with InspectTree
  -- I have no idea how to get this content via treesitter....
  if type == 'minus_metadata' then
    local next_child = node:iter_children()
    local metadata_content = next_child()
    while metadata_content do
      print("frontmatter node " .. metadata_content:type())
      next_child()
    end

    return {}
  end

  if (type == 'atx_heading') then
    local marker = node:child(0):type()
    local content = node:child(1)
    local heading_lvl = 1
    if content then
      if not marker then
        return {}
      elseif marker == 'atx_h1_marker' then
        heading_lvl = 1
      elseif marker == 'atx_h2_marker' then
        heading_lvl = 2
      elseif marker == 'atx_h3_marker' then
        heading_lvl = 3
      elseif marker == 'atx_h4_marker' then
        heading_lvl = 4
      else
        return wrapped_error_element("unkown heading marker " .. marker)
      end

      local heading_element = {
        type = ELEMENT_TYPES.heading,
        level = heading_lvl,
        content = vim.treesitter.get_node_text(content, 0)
      }
      return { heading_element }
    end

    return {}
  end


  if (type == 'paragraph') then
    local paragraph_elements = {}
    local next_content = node:iter_children()
    local content = next_content()
    if content then
      local result = parse_paragraph_contents(content, ctx) -- deeper parsing needed
      utils.insert_all(paragraph_elements, result)
      content = next_content()
    end

    return paragraph_elements
  end

  if (type == 'list') then
    local next_list_item = node:iter_children()
    local list_item = next_list_item()

    local markerType = list_item:child(0):type()
    local is_ordered = false
    if (markerType == 'list_marker_dot') then
      is_ordered = true
    end

    local elements = {}
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


        local new_context = {}
        for k, v in pairs(ctx) do
          new_context[k] = v
        end
        new_context.checked = checked

        if content:type() == "list" then
          new_context.indent = new_context.indent + 1
        end

        local new_elements = parse_node(content, new_context)
        utils.insert_all(elements, new_elements)

        content = next_content()
      end

      list_item = next_list_item()
    end

    local list_element = {
      type = ELEMENT_TYPES.list,
      indent = ctx.indent,
      is_ordered = is_ordered,
      items = elements
    }
    return { list_element }
  end

  if (type == 'fenced_code_block') then
    local next_content = node:iter_children()

    local program_element = {
      type = ELEMENT_TYPES.code,
    }

    local content_item = next_content()
    while content_item do
      if content_item:type() == 'code_fence_content' then
        program_element.content = vim.treesitter.get_node_text(content_item, 0)
      end

      if content_item:type() == 'info_string' then
        local next_info = content_item:iter_children()
        local info_item = next_info()
        while info_item do
          if info_item:type() == 'language' then
            program_element.language = vim.treesitter.get_node_text(info_item, 0)
          end
          info_item = next_info()
        end
      end

      content_item = next_content()
    end

    return { program_element }
  end

  return wrapped_error_element("unknown node type " .. type)
end


M.parse_current_buffer = function()
  local root_node = get_root_node()
  if root_node then
    return parse_node(root_node)
  end
  return {}
end

return M
