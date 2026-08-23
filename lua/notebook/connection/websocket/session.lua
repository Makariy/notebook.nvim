local Handshake = require("notebook.connection.websocket.handshake")
local Assembler = require("notebook.connection.websocket.message_assembler")
local frame_codec = require("notebook.connection.websocket.frame_codec")

---@class WebSocketSession
---@field transport ITransport
---@field assembler MessageAssembler
---@field state "INIT" | "HANDSHAKING" | "CONNECTED" | "CLOSED"
---@field read_buffer string
---@field handshake_key? string
---@field on_open? fun()
---@field on_message? fun(msg: string)
---@field on_close? fun()
---@field on_error? fun(err: string)
local WSSession = {}
WSSession.__index = WSSession

---@param transport ITransport
---@return WebSocketSession
function WSSession.new(transport)
	local self = setmetatable({}, WSSession)
	self.transport = transport
	self.assembler = Assembler.new()
	self.state = "INIT"
	self.read_buffer = ""
	return self
end

---@param host string
---@param port integer
---@param path string
---@param on_open? fun()
---@param on_message? fun(msg: string)
---@param on_close? fun()
---@param on_error? fun(err: string)
function WSSession:connect(host, port, path, on_open, on_message, on_close, on_error)
	self.on_open = on_open
	self.on_message = on_message
	self.on_close = on_close
	self.on_error = on_error

	self.transport:connect(host, port, function(err)
		if err then
			return self:_close_with_error("Transport connection failed: " .. err)
		end

		self.state = "HANDSHAKING"
		local request, key = Handshake.build_request(host, port, path)
		self.handshake_key = key
		self.transport:write(request)

		self.transport:read_start(function(read_err, chunk)
			if read_err or not chunk then
				return self:close()
			end
			self:_handle_chunk(chunk)
		end)
	end)
end

---@private
---@param chunk string
function WSSession:_handle_chunk(chunk)
	self.read_buffer = self.read_buffer .. chunk

	if self.state == "HANDSHAKING" then
		local is_done, err, rest = Handshake.parse_response(self.read_buffer, self.handshake_key)
		if not is_done then
			return
		end

		if err then
			return self:_close_with_error(err)
		end

		self.read_buffer = rest
		self.state = "CONNECTED"
		if self.on_open then
			self.on_open()
		end
	end

	if self.state == "CONNECTED" then
		self:_process_frames()
	end
end

---@private
function WSSession:_process_frames()
	while true do
		local frame, rest = frame_codec.try_parse(self.read_buffer)
		if not frame then
			break
		end

		self.read_buffer = rest

		if frame.opcode == frame_codec.OPCODE.CLOSE then
			self:close()
			break
		elseif frame.opcode == frame_codec.OPCODE.PING then
			self.transport:write(frame_codec.encode(frame.payload, frame_codec.OPCODE.PONG))
		else
			local complete_msg = self.assembler:process(frame)
			if complete_msg and self.on_message then
				self.on_message(complete_msg)
			end
		end
	end
end

---@param text string
function WSSession:send(text)
	if self.state ~= "CONNECTED" then
		vim.notify("WebSocket send ignored: state is " .. self.state, vim.log.levels.WARN)
		return
	end
	self.transport:write(frame_codec.encode(text, frame_codec.OPCODE.TEXT))
end

function WSSession:close()
	if self.state == "CLOSED" then
		return
	end

	local was_connected = (self.state == "CONNECTED")
	self.state = "CLOSED"

	if was_connected then
		local close_frame = frame_codec.encode("", frame_codec.OPCODE.CLOSE)
		self.transport:write(close_frame, function()
			self.transport:close()
		end)
	else
		self.transport:close()
	end

	if self.on_close then
		self.on_close()
	end
end

---@private
---@param err_msg string
function WSSession:_close_with_error(err_msg)
	vim.notify(err_msg, vim.log.levels.ERROR)
	if self.on_error then
		self.on_error(err_msg)
	end
	self:close()
end

return WSSession
