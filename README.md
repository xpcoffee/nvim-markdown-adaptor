# nvim-markdown-adaptor

[Neovim](https://neovim.io/) plugin which adapts markdown files to external targets (one-way sync).

> WARNING❗❗ This repo is real-buggy, and not ready for public consumption. Use at your own risk. ❗❗WARNING

## Goals (as of 2024-08)

- What: be able to sync a markdown file to/from a target, initially google-docs.
- Why: keep your files in markdown; adapt them into what you need, when you need it.

<img src="https://github.com/user-attachments/assets/bfdfb53f-13b9-4c2e-8caf-6cf5130846f8" width="300px;"></img>

## Getting started

### Steps to set up a Google Application

You need an application in order to get credentials to modify your Google Docs.

- Create an account & project https://cloud.google.com/apis/docs/getting-started
- Enable the Google Docs API for the project https://console.cloud.google.com/apis/library/docs.googleapis.com
- Create an OAuth client ID https://console.cloud.google.com/apis/credentials
- Download the "OAuth client" secrets file and save it to `/home/rick/.nvim-extension-client-secret.json`
  - TODO: this is currently hardcoded in `google_docs_api.lua`, but should be configured

### Installation

The project has a dependency on [pegasus](https://github.com/EvandroLG/pegasus.lua). This needs to be manually installed e.g. using [luarocks](https://luarocks.org/).
TODO: automate this as part of the config (for some reason I haven't been able to get luarocks.nvim to work with this)

```shell
luarocks install pegasus
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "xpcoffee/nvim-markdown-adaptor",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    google_client_file_path = "/home/rick/.nvim-extension-client-secret.json", -- required
    data_file_path = "/home/rick/.nvim-markdown-adaptor.json", -- make sure this file exists; it doesn't get auto-created
  },
}
```

If you want to use a `config` clause, you need to call `setup()` with opts.

```lua
{
  "xpcoffee/nvim-markdown-adaptor",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local adaptor = require('nvim-markdown-adaptor')
    vim.keymap.set("n", "<leader>mg", adaptor.sync_to_google_doc, { desc = "markdown: to Google Doc"})
    adaptor.setup({
        google_client_file_path = "/home/rick/.nvim-extension-client-secret.json", -- required
        data_file_path = "/home/rick/.nvim-markdown-adaptor.json",
    })
  end
}
```

### Opts

- `google_client_file_path` | required | _string_ | _default: nil_ | A path to persist data, incl OAuth2 refresh token. If left empty, no data will be persisted. e.g. you'll need to authorize every session.
- `data_file_path` | optional | _string_ | _default: nil_ | A path to persist data, incl OAuth2 refresh token. If left empty, no data will be persisted. e.g. you'll need to authorize every session.
- `google_oauth_redirect_port` | optional | _string_ | _default: "9090"_ | The port to use when listening to OAuth2 loopback

### Usage

On a markdown page:

```lua
-- sync to a specific document
require "nvim-markdown-adaptor".sync_to_google_doc({ document_id = "your-gdoc-id"})

-- re-do the auth flow to get credentials to call against the Google API
require "nvim-markdown-adaptor".reauthorize_google_api()
```

TODO: grab document ID from the frontmatter or allow input.

## Known issues

- We currently do not check expiry of the OAuth refresh-token. Need to trigger `reauthorize_google_api` manually to get a new one.

## Research

Progress made while figuring out how to get htis to work.

### 2024-08-26

Quite close to a working prototype now

- [x] transform parser output into google docs commands
- [x] update a doc - "hello world" on document
- [x] replace doc with new content
- [ ] support elements
  - [x] headings
  - [x] paragraphs
  - [x] code
  - [x] lists
  - [x] checklists
  - [ ] links
  - [ ] quotes
- [ ] update readme to enable someone else to install
- [ ] define actual MVP scope

Out of scope for now

- tables
- images

### 2024-08-25

Now know how to do an Oauth flow

- [x] figure out how to perform oauth2 flow to authorize the plugin to update docs
  - [x] have an endpoint where we listen for the redirect
    - [x] start pegasus server from vim
  - [x] exchange code for an access token & refresh in pegasus server
  - [x] return access token & refresh token to vim
  - [x] store the refresh token

Corners cut

- using plain code verifier instead of SHA256 (was getting stuck on the latter; what we want is a proof-of-concept so deferring the encrypted challenge)

Next steps

- transform parser output into google docs commands
- update a doc

### 2024-08-24

Minor progress...

- [ ] figure out how to perform oauth2 flow to authorize the plugin to update docs
  - [ ] have an endpoint where we listen for the redirect
    - [x] start pegasus server from vim
    - [ ] exchange code for an access token & refresh in pegasus server
    - [ ] return access token & refresh token to vim
    - [ ] store the refresh token

### 2024-08-18 OAuth2

Since last time:

- [x] use treesitter's syntax tree to generate a list of entities
- [x] make calls against google api from the plugin
  - uses plenary's curl
  - not authorized, so currently returns a 401
- [x] figure out format for updating google doc
  - [get content range of document](https://developers.google.com/docs/api/reference/rest/v1/documents/get)
  - [batch update](https://developers.google.com/docs/api/reference/rest/v1/documents/request): delete content, list of requests to insert new content
- [ ] figure out how to perform oauth2 flow to authorize the plugin to update docs
  - [x] generate auth URL
  - [x] generate redirect URL (gets called after user gives consent)
  - [ ] have an endpoint where we listen for the redirect <--- this is currently a blocker; attempts to spin up a server from within the plugin have not been successful
    - [this happens here](https://github.com/googlesamples/oauth-apps-for-windows/blob/master/OAuthConsoleApp/OAuthConsoleApp/Program.cs#L99) in examples, but I don't see equivalent tooling for lua...
    - tried pegasus server & spinning it up both using `uv.new_work` (pegasus not available in thread), `uv.new_thread` (cross-boundary c-calls), and `plenary.async.wrap + run` (pegasus not available in thread)
    - next step: separate server binary that gets invoked? need a communication between them
  - [ ] store the refresh token
  - [ ] exchange refresh token for an access token

### 2024-07-21 Treesitter

nvim has [treesitter](https://neovim.io/doc/user/treesitter.html), which gives access to a syntax tree.

We could reduce markdown nodes in the tree to a set of [Google docs update requests](https://developers.google.com/docs/api/reference/rest/v1/documents/request#Request) and batch update using those requests.

This is roughly what I'm thinking for creating a new doc

```
# pseudocode
func bufferToUpdateRequests() {
  var gdocUpdateRequests = []
  for mdNode in vim.buff.tree.nodes {
    gdocUpdateRequests.push(
       toGdocRequest(mdNode)
    )
  }
  return gdocUpdateRequests
}

var gdocId = GDocsApi.createNewDocument()
var updates = bufferToUpdateRequests()
GDocsApi.batchUpdate(gdocId, updates)

# link to the document is saved in frontmatter
updateOrCreateFrontMatterWithGdocId(gdocId)
```

Updating a doc seems tricky. As a first step I think deleting all contents of a doc and re-uploading is simplest.

> note: we don't want to delete the doc and create a new one, as we'll be sharing that doc's ID with people and we want that to stay unchanged

```
# pseudocode
var gdocId = getGdocIdFromFrontMatter()

var body = GDocsApi.get(gdocId).body
var bodyRange = GDocs.Range(body.start, body.end)
GDocsApi.deleteContentRange(bodyRange)

var updates = bufferToUpdateRequests()
GDocsApi.batchUpdate(gdocId, updates)
```

### 2024-06-19 [discarded] Pandoc workflow

Idea

- convert buffer to some document format (odt/docx) using pandoc
- upload the result to a google doc

Doesn't seem like it would work

- [you can upload the output doc to Google Drive](https://stackoverflow.com/questions/60387029/google-docs-api-delete-all-content) and select "open with Docs", but that creates a new GoogleDoc (doesn't update the existing doc); this means it can't be kept up-to-date this way. I also can't seem to find a way to automate the conversion of the drive file into a doc: looks like this happens via some private calls on the Google end.
  ```
  posts against clients6.google.com/batch/drive/v2internal
  POST request body: POST /drive/v2internal/files/<file-id>/copy
  POST request body: GET /drive/v2internal/changes
  # bit weird that the POST body defines a GET...
  ```
- [Google docs API doesn't seem to accept full files](https://developers.google.com/docs/api/reference/rest/v1/documents/request#Request); you instead need to make multiple updates for each type of element you want in your doc (header, paragraph, table, etc). Using markdown in the when inserting text (example below) does not result in correct formatting.
  ```json
  {
    "requests": [
      {
        "insertText": {
          "text": "# this is a header\n\nthis is a paragraph\n\n- this is\n- a bullet list\n\n",
          "location": {
            "index": 1
          }
        }
      }
    ]
  }
  ```
- [non-blocker] Replacing all the text in a document requires [fetching the document first](https://stackoverflow.com/questions/60387029/google-docs-api-delete-all-content)
