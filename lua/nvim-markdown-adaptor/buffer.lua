local loop = vim.loop
local api = vim.api

local function convertFile()
    local shortname = vim.fn.expand('%:t:r')
    local fullname = api.nvim_buf_get_name(0)

    handle = loop.spawn(
        'pandoc',
        {
            args = {
                fullname,
                '--to=odt',
                '-o', string.format('/tmp/%s.html', shortname),
                '-s',
                '-c',
            },
        },
        function(code, signal) -- on exit
            print(string.format("Document conversion complete! %s %s", code, signal))
            handle:close()
        end
    )
end

return {
    convertFile = convertFile
}
