local TcpTransport = require("notebook.connection.websocket.transport")

---@class HttpResponse
---@field status integer
---@field headers table<string, string>
---@field body string

---@class HttpClient
---@field host string
---@field port integer
local HttpClient = {}
HttpClient.__index = HttpClient

---@param host string
---@param port integer
---@return HttpClient
function HttpClient.new(host, port)
	local self = setmetatable({}, HttpClient)
	self.host = host
	self.port = port
	return self
end

---@param raw string
---@param force boolean
---@return HttpResponse?, boolean complete
function HttpClient.parse_response(raw, force)
	local header_end = raw:find("\r\n\r\n")
	if not header_end then
		return nil, false
	end

	local header_str = raw:sub(1, header_end - 1)
	local body_start = header_end + 4
	local status = tonumber(header_str:match("^%S+ (%d+)")) or 500

	local headers = {}
	for line in header_str:gmatch("[^\r\n]+") do
		local key, value = line:match("^(.-):%s*(.*)$")
		if key then
			headers[key:lower()] = value
		end
	end

	local content_length = tonumber(headers["content-length"])
	if content_length then
		if #raw < body_start + content_length - 1 then
			return nil, false
		end
		return {
			status = status,
			headers = headers,
			body = raw:sub(body_start, body_start + content_length - 1),
		},
			true
	end

	if force then
		return { status = status, headers = headers, body = raw:sub(body_start) }, true
	end

	return nil, false
end

---@param method "GET" | "POST" | "DELETE"
---@param path string
---@param body? string
---@param on_response fun(err: string?, res: HttpResponse?, err_code: string?)
---@param timeout_ms? integer
function HttpClient:request(method, path, body, on_response, timeout_ms)
	timeout_ms = timeout_ms or 5000
	local transport = TcpTransport.new()
	local payload = body or ""
	local raw_buf = ""
	local finished = false

	local timer = vim.uv.new_timer()
	if not timer then
		error("Timer could not be created")
	end

	local function finish(err, res, err_code)
		if finished then
			return
		end
		finished = true
		timer:stop()
		timer:close()
		transport:close()
		on_response(err, res, err_code)
	end

	timer:start(
		timeout_ms,
		0,
		vim.schedule_wrap(function()
			finish(
				string.format("HTTP request timed out: %s %s on %s:%d", method, path, self.host, self.port),
				nil,
				"TIMEOUT"
			)
		end)
	)

	local req = table.concat({
		string.format("%s %s HTTP/1.1", method, path),
		string.format("Host: %s:%d", self.host, self.port),
		"Content-Type: application/json",
		"Content-Length: " .. tostring(#payload),
		"Connection: close",
		"",
		payload,
	}, "\r\n")

	transport:connect(self.host, self.port, function(connect_err)
		if connect_err then
			return finish(
				string.format("HTTP connection failed to %s:%d: %s", self.host, self.port, connect_err),
				nil,
				connect_err
			)
		end

		transport:write(req)
		transport:read_start(function(read_err, chunk)
			if read_err then
				return finish(read_err, nil, read_err)
			end

			if chunk then
				raw_buf = raw_buf .. chunk
				local res, complete = HttpClient.parse_response(raw_buf, false)
				if complete then
					finish(nil, res, nil)
				end
			else
				local res, complete = HttpClient.parse_response(raw_buf, true)
				if complete then
					finish(nil, res, nil)
				else
					finish(
						string.format(
							"Malformed HTTP response from %s:%d for %s %s",
							self.host,
							self.port,
							method,
							path
						),
						nil,
						"MALFORMED"
					)
				end
			end
		end)
	end)
end

return HttpClient
