local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol

local WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

local Handshake = {}

---@private
---@param data string
---@return string hex digest
local function sha1(data)
	local bit_len = #data * 8

	local msg = data .. "\128"
	local pad = (56 - (#msg % 64)) % 64
	if pad > 0 then
		msg = msg .. string.rep("\0", pad)
	end

	local length_str = {}
	local v = bit_len
	for i = 8, 1, -1 do
		length_str[i] = string.char(v % 256)
		v = math.floor(v / 256)
	end
	msg = msg .. table.concat(length_str)

	local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

	local w = {}
	for start = 1, #msg, 64 do
		for i = 0, 15 do
			local o = start + i * 4
			w[i] = bor(
				lshift(string.byte(msg, o), 24),
				lshift(string.byte(msg, o + 1), 16),
				lshift(string.byte(msg, o + 2), 8),
				string.byte(msg, o + 3)
			)
		end
		for i = 16, 79 do
			w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
		end

		local a, b, c, d, e = h0, h1, h2, h3, h4
		for i = 0, 79 do
			local f, k
			if i < 20 then
				f = bor(band(b, c), band(bnot(b), d))
				k = 0x5A827999
			elseif i < 40 then
				f = bxor(b, c, d)
				k = 0x6ED9EBA1
			elseif i < 60 then
				f = bor(band(b, c), band(b, d), band(c, d))
				k = 0x8F1BBCDC
			else
				f = bxor(b, c, d)
				k = 0xCA62C1D6
			end

			local temp = (rol(a, 5) + f + e + k + w[i]) % 4294967296
			e = d
			d = c
			c = rol(b, 30)
			b = a
			a = temp
		end

		h0 = (h0 + a) % 4294967296
		h1 = (h1 + b) % 4294967296
		h2 = (h2 + c) % 4294967296
		h3 = (h3 + d) % 4294967296
		h4 = (h4 + e) % 4294967296
	end

	local function to_bytes(n)
		return string.char(
			band(rshift(n, 24), 0xff),
			band(rshift(n, 16), 0xff),
			band(rshift(n, 8), 0xff),
			band(n, 0xff)
		)
	end

	return to_bytes(h0) .. to_bytes(h1) .. to_bytes(h2) .. to_bytes(h3) .. to_bytes(h4)
end

---@private
---@param key string
---@return string
function Handshake.expected_accept(key)
	return vim.base64.encode(sha1(key .. WEBSOCKET_GUID))
end

---@param host string
---@param port integer
---@param path string
---@return string request, string key
function Handshake.build_request(host, port, path)
	local bytes = {}
	for i = 1, 16 do
		bytes[i] = string.char(math.random(0, 255))
	end
	local key = vim.base64.encode(table.concat(bytes))

	local request = table.concat({
		string.format("GET %s HTTP/1.1", path),
		string.format("Host: %s:%d", host, port),
		"Upgrade: websocket",
		"Connection: Upgrade",
		"Sec-WebSocket-Key: " .. key,
		"Sec-WebSocket-Version: 13",
		"",
		"",
	}, "\r\n")

	return request, key
end

---@private
---@param headers string
---@param name string
---@return string?
local function find_header(headers, name)
	for line in headers:gmatch("[^\r\n]+") do
		local key, value = line:match("^(.-):%s*(.*)$")
		if key and key:lower() == name then
			return value
		end
	end
	return nil
end

---@param buffer string
---@param key? string
---@return boolean is_complete, string? error_msg, string remaining_buffer
function Handshake.parse_response(buffer, key)
	local header_end = buffer:find("\r\n\r\n")
	if not header_end then
		return false, nil, buffer
	end

	local headers = buffer:sub(1, header_end + 3)
	local remaining = buffer:sub(header_end + 4)

	local status_line = headers:match("^%S+ (%d+)")
	if not status_line or status_line ~= "101" then
		return true, "Server rejected websocket upgrade:\n" .. headers, remaining
	end

	if key then
		local accept = find_header(headers, "sec-websocket-accept")
		if not accept or accept ~= Handshake.expected_accept(key) then
			return true, "Invalid Sec-WebSocket-Accept in handshake response", remaining
		end
	end

	return true, nil, remaining
end

return Handshake
