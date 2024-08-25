# nvim-markdown-adaptor

nvim plugin which adapts markdown files to external targets

> WIP. This repo doesn't do anything currenlty.

## goals (as of 2024-06)

- be able to sync a markdown file to/from a target, initially google-docs

## research

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
