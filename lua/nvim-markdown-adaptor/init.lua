local adaptor = require('nvim-markdown-adaptor.google_docs_adaptor')
local gapi = require('nvim-markdown-adaptor.google_docs_api')
local settings = require('nvim-markdown-adaptor.settings')

settings.load_from_file() -- todo: do this in a config hook

return {
  sync_to_google_doc = adaptor.sync_to_google_doc,
  reauthorize_google_api = function()
    gapi:oAuth2({ force_auth_flow = true })
  end
}
