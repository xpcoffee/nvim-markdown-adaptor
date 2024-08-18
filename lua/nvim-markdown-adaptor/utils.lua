local M = {}

local uv = vim.loop

-- Adds all values from one table to another table
--
---@param list table
---@param newValues table
M.insert_all = function(list, newValues)
  for _, value in pairs(newValues) do
    table.insert(list, value)
  end
end

-- Reads the contents of a file and returns them in a callback
M.read_file = function(path, callback)
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

return M
