local adaptor = require('nvim-markdown-adaptor.google_docs_adaptor')
local settings = require('nvim-markdown-adaptor.settings')

settings.load_from_file()

return {
  adapt_current_buffer = adaptor.adapt_current_buffer,
}
