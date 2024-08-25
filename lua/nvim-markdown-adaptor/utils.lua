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
  local permission = 256 -- 0400 in octal; only user can read
  uv.fs_open(path, "r", permission, function(err, fd)
    assert(not err, err)
    if err then
      error(err)
      callback(nil)
      return
    end

    if (fd == nil) then
      return
    end

    uv.fs_fstat(fd, function(err, stat)
      if err then
        error(err)
        callback(nil)
        return
      end

      if (stat == nil) then
        return
      end

      uv.fs_read(fd, stat.size, 0, function(err, data)
        if err then
          error(err)
          callback(nil)
          return
        end

        uv.fs_close(fd, function(err)
          if not err then
            callback(data)
          else
            error(err)
            callback(nil)
          end
        end)
      end)
    end)
  end)
end

M.write_file = function(path, file_contents, callback)
  local permission = 384 -- 0600 in octal; only user can read/write
  uv.fs_open(path, "w", permission, function(err, fd)
    assert(not err, err)
    if (fd == nil) then
      return
    end

    uv.fs_write(fd, file_contents, 0, function(err)
      assert(not err, err)
      uv.fs_close(fd, function(err)
        assert(not err, err)
        callback()
      end)
    end)
  end)
end

return M
