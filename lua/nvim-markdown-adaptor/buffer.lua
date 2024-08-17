local M = {}

local FRONTMATTER_GOOGLE_DOC_ID_KEY = 'google-doc-id'

local curl = require("plenary.curl")
local uv = vim.loop


local function getRootNode()
  local node = vim.treesitter.get_node({ pos = { 0, 0 } })

  while (node ~= nil and node:parent() ~= nil) do
    node = node:parent()
  end

  return node
end

---@param list table
---@param newValues table
local function insertAll(list, newValues)
  for _, value in pairs(newValues) do
    print(value)
    table.insert(list, value)
  end
end

local function getErrorCommand(msg)
  return { string.format('{"type": "error", "msg":"%s"}', msg) }
end

---@param node TSNode
---@return table
local function toGoogleDocCommands(node)
  local type = node:type()

  if (type == 'document' or type == 'section') then
    local commands = {}
    local child_iter = node:iter_children()
    local child = child_iter()
    while child ~= nil do
      local newCommands = toGoogleDocCommands(child)
      insertAll(commands, newCommands)
      child = child_iter()
    end
    return commands
  end

  if type == 'minus_metadata' then
    local map = node:child(0)
    print(string.format("count: %s", node:child_count()))

    while (map ~= nil and map:type() ~= 'block_mapping') do
      print("type " .. map:type())
      map = map:child(0)
    end

    if map == nil then
      print("we not mapping ")
      return {}
    end
    print("we mapping ")
    local pairs_iterator = map:iter_children()
    local pair = pairs_iterator()
    while (pair ~= nil) do
      local key = pair:child(0)
      local value = pair:child(1)
      if (key ~= nil and value ~= nil) then
        local key_text = vim.treesitter.get_node_text(key, 0)
        print("key " .. key_text)
        if (key_text == FRONTMATTER_GOOGLE_DOC_ID_KEY) then
          local frontmatter_command = string.format('{"type": "frontmatter", "googleDocId": "%s"}',
            vim.treesitter.get_node_text(value, 0))
          return { frontmatter_command }
        end
      end
    end
    return {}
  end

  if (type == 'atx_heading') then
    local marker = node:child(0):type()
    local content = node:child(1)
    local heading = 1
    if (content ~= nil) then
      if (marker ~= nil and marker == 'atx_h1_marker') then
        heading = 1
      elseif (marker ~= nil and marker == 'atx_h2_marker') then
        heading = 2
      elseif (marker ~= nil and marker == 'atx_h3_marker') then
        heading = 3
      elseif (marker ~= nil and marker == 'atx_h4_marker') then
        heading = 4
      else
        return getErrorCommand("unkown heading marker " .. marker)
      end

      local heading_command = string.format('{"type": "heading%s", "content": "%s"}', heading,
        vim.treesitter.get_node_text(content, 0))
      return { heading_command }
    end

    return {}
  end


  if (type == 'paragraph') then
    local content = node:child(0)
    if (content ~= nil) then
      local paragraph_command = string.format('{"type": "paragraph", "content": "%s"}',
        vim.treesitter.get_node_text(content, 0))
      return { paragraph_command }
    else
      return { "empty" }
    end
  end

  if (type == 'list') then
    local child_iter = node:iter_children()
    local list_item = child_iter()

    local markerType = list_item:child(0):type()
    local isOrdered = false
    if (markerType == 'list_marker_dot') then
      isOrdered = true
    end

    local commands = {}
    while list_item ~= nil do
      local list_item_content = list_item:child(1)
      if (list_item_content ~= nil) then
        local newCommands = toGoogleDocCommands(list_item_content)
        insertAll(commands, newCommands)
      end
      list_item = child_iter()
    end

    local list_command = string.format('{"type": "list", "ordered": %s, "items": [%s] }', isOrdered,
      table.concat(commands, ','))
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
      local program_content = vim.treesitter.get_node_text(program, 0)
      local program_command = string.format('{"type": "code", "language":"%s", "content": "%s" }', language,
        program_content)
      return { program_command }
    end
  end

  return getErrorCommand("unknown node type " .. type)
end

-- delete later ... for reference only
local function exampleFetch()
  curl.get("https://dummyjson.com/test", {
    callback = vim.schedule_wrap(function(res)
      local result = vim.json.decode(res.body)
      for k, v in pairs(result) do
        print(k .. ": " .. v)
      end
    end)
  })
end

local function bufferToCommands()
  local root = getRootNode()
  if (root ~= nil) then
    local commands = toGoogleDocCommands(root)
    for _, command in pairs(commands) do
      print(command)
    end
  end
end

local read_file = function(path, callback)
  uv.fs_open(path, "r", 438, function(err, fd)
    assert(not err, err)
    if (fd == nil) then
      return
    end

    uv.fs_fstat(fd, function(err, stat)
      assert(not err, err)
      if (stat == nil) then
        return
      end

      uv.fs_read(fd, stat.size, 0, function(err, data)
        assert(not err, err)
        uv.fs_close(fd, function(err)
          assert(not err, err)
          callback(data)
        end)
      end)
    end)
  end)
end

local googleDocs = {
  apiKey = "AIzaSyA3I1gibID13FmT6H6Nrh6-g-O_TmPLgzg",
  clientId = "1061313657775-3tvcrig9qi4lhe0331pgmme8bsgj0pti.apps.googleusercontent.com",
  clientSecretsFile = "/home/rick/.nvim-extension-client-secret.json"
}

googleDocs.getClientSecret = function(this, params)
  read_file(this.clientSecretsFile, function(data)
    local secretsData = vim.json.decode(data)
    params.callback(secretsData.installed.client_secret)
  end)
end

googleDocs.oAuth2 = function(this, params)
  print("Authorizing access to Google Docs...")

  googleDocs:getClientSecret({
    callback = function(client_secret)
      print("secret " .. client_secret)

      -- check if we have access token
      --  - true: return
      --  - false: check if we have refresh token
      --      - true:
      --        - call exchange endpoint to get access token
      --        - store access token in this session
      --      - false:
      --        - prepare url for oauth2 consent
      --        - start http listener to listen to loopback call
      --        - prompt user to open in browser
      --        - on loopback call recieved
      --          - store refresh token
      --          - call exchange endpoint to get access token
      --          - store access token in this session
      --

      print("Google authorization successful")
      params.callback()
    end
  })
end

googleDocs.get = function(this, params)
  print("fetching details for " .. params.documentId)
  local url = ("https://docs.googleapis.com/v1/documents/" ..
    params.documentId .. "?key=" .. this.apiKey)

  --- FIXME: currently failing  with 401 here
  local onResponse = vim.schedule_wrap(function(response)
    print(vim.json.encode(response))
    local body = vim.json.decode(response.body)
    params.callback(body)
  end)

  curl.get(url, { callback = onResponse })
end

function replaceGoogleDocContents(document)
  print("replacing contents of " .. document.id)
  local elements = document.body.content
  local documentRange = {
    startIndex = 0,
    endIndex = elements[#elements].endIndex
  }

  local batchUpdateRequest = vim.json.encode({
    documentId = document.id,
    requests = {
      {
        deleteContentRange = {
          range = documentRange
        }
      },
      {
        insertText = {
          text = "hello world!\nhow are ya!"
        }
      },
      {
        insertText = {
          text = "bonjour monde!"
        }
      }
    },
  })

  print(batchUpdateRequest)
end

local function updateGoogleDoc()
  local docId = "1MlkhxLgUxsol_zN6Irhy6jhcPSPZLKulBMV-YPSU6Bg"

  googleDocs:oAuth2({
    callback = googleDocs:get({
      documentId = docId,
      callback = replaceGoogleDocContents
    })
  })
end

M.convertFile = function()
  vim.schedule_wrap(updateGoogleDoc)()
end

return M
