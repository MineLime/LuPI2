local internet = {}

function internet.start()
  local component = {}

  --Legacy
  function component.isHttpEnabled()
    return true
  end

  function component.isTcpEnabled()
    return true
  end

  --Old TCP
  function component.connect(address, port)
    checkArg(1, address, "string")
    checkArg(2, port, "number", "nil")
    if not port then
      address, port = address:match("(.+):(.+)")
      port = tonumber(port)
    end

    local sfd, reason = net.open(address, port)
    local closed = false
    return {
      finishConnect = function()
        if not sfd then
          error(reason)
        end
        return true
      end,
      read = function(n)
        if closed then return nil, "connection lost" end
        n = n or 65535
        checkArg(1, n, "number")
        local data = net.read(sfd, n)
        if not data then
          closed = true
          native.fs_close(sfd)
          return nil, "connection lost"
        end
        return data
      end,
      write = function(data)
        if closed then return nil, "connection lost" end
        checkArg(1, data, "string")
        local written = net.write(sfd, data)
        if not written then
          closed = true
          native.fs_close(sfd)
          return nil, "connection lost"
        end
        return written
      end,
      close = function()
        closed = true
        native.fs_close(sfd)
      end
    }
  end

  function component.request(url, post)
    checkArg(1, url, "string")
    checkArg(2, post, "string", "nil")
    local host, uri = url:match("https?://([^/]+)([^#]+)")
    if not host then native.log("internet.request host match error: " .. url .. "\n") end
    local socket = component.connect(host, 80)
    if socket.finishConnect() then
      local request
      if not post then
        request = "GET " .. uri .. " HTTP/1.1\r\nHost: " .. host .. "\r\nConnection: close\r\n\r\n"
      else
        request = "POST " .. uri .. " HTTP/1.1\r\nHost: " .. host .. "\r\nConnection: close\r\n"
          .. "Content-Type: application/x-www-form-urlencoded\r\nUser-Agent: LuPI/1.0\r\n"
          .. "Content-Length: " .. math.floor(#post) .. "\r\n\r\n"
          .. post .. "\r\n\r\n"
      end
      socket.write(request)
      if native.debug then
        native.log("internet.request:\n-- request begin --\n" .. request .. "\n-- request end --")
      end
    end

    local stream = {}

    function stream:seek()
      return nil, "bad file descriptor"
    end

    function stream:write()
      return nil, "bad file descriptor"
    end

    function stream:read(n)
      if not socket then
        return nil, "connection is closed"
      end
      return socket.read(n)
    end

    function stream:close()
      if socket then
        socket.close()
        socket = nil
      end
    end

    local connection = modules.buffer.new("rb", stream)
    connection.readTimeout = 10
    local header = nil

    --TODO: GC close
    --TODO: Chunked support

    local finishConnect = function() --Read header
      header = {}
      header.status = connection:read("*l"):match("HTTP/.%.. (%d+) (.+)\r")
      if native.debug then
        native.log("internet.request:\n-- response begin --\n" .. header.status .. "\n")
      end
      while true do
        local line = connection:read("*l")
        if not line or line == "" or line == "\r" then
          break
        end
        local k, v = line:match("([^:]+): (.+)\r")
        header[k:lower()] = v
        if native.debug then
          native.log(line)
        end
      end
      if native.debug then
        native.log("-- response end --")
      end
      header["content-length"] = tonumber(header["content-length"])
    end

    return {
      finishConnect = finishConnect,
      read = function(n)
        if not header then
          finishConnect()
        end
        if not header["content-length"] or header["content-length"] < 1 then
          return nil
        end
        checkArg(1, n, "number", "nil")
        n = n or math.min(8192, header["content-length"])
        local res = connection:read(n)
        header["content-length"] = header["content-length"] - #res
        return res
      end,
      close = function()
        connection:close()
      end
    }
  end

  modules.component.api.register(nil, "internet", component)
end

return internet
