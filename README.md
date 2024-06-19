# nvim-markdown-adaptor
nvim plugin which adapts markdown files to external targets

## goals

 - be able to sync a markdown file to/from a target, initially google-docs

## research

### 2024-06-19 Pandoc workflow

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
