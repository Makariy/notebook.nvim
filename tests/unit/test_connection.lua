local frame_codec = require("notebook.connection.websocket.frame_codec")
local Handshake = require("notebook.connection.websocket.handshake")
local Assembler = require("notebook.connection.websocket.message_assembler")
local HttpClient = require("notebook.connection.http.client")

-- encode/try_parse round trip across every length-prefix boundary.
do
	for _, len in ipairs({ 0, 1, 125, 126, 127, 200, 65535, 65536, 70000 }) do
		local payload = string.rep("x", len)
		local frame = frame_codec.encode(payload, frame_codec.OPCODE.TEXT)
		local parsed, rest = frame_codec.try_parse(frame)
		check(parsed ~= nil, "WS1 frame parses for length " .. len)
		check(
			parsed ~= nil and parsed.payload == payload and parsed.opcode == frame_codec.OPCODE.TEXT and parsed.fin,
			"WS1 payload/opcode/fin for length " .. len
		)
		check(rest == "", "WS1 no leftover bytes for length " .. len)
	end
end

-- A frame split at any byte is not parsed until complete.
do
	local payload = string.rep("y", 100)
	local frame = frame_codec.encode(payload, frame_codec.OPCODE.TEXT)
	for cut = 1, #frame - 1 do
		local parsed = frame_codec.try_parse(frame:sub(1, cut))
		check(parsed == nil, "WS2 truncated frame yields nil at byte " .. cut)
	end
	local parsed, rest = frame_codec.try_parse(frame)
	check(parsed ~= nil and parsed.payload == payload, "WS2 the complete frame parses")
	check(rest == "", "WS2 complete frame leaves no bytes")
end

-- Handshake request shape and response validation.
do
	local req, key = Handshake.build_request("127.0.0.1", 8888, "/api/kernels/x/channels")
	check(req:find("GET /api/kernels/x/channels HTTP/1.1") == 1, "WS3 request line")
	check(
		req:find("Upgrade: websocket") ~= nil and req:find("Sec-WebSocket-Key: " .. key, 1, true) ~= nil,
		"WS3 upgrade headers"
	)

	local accept = Handshake.expected_accept(key)
	local response = table.concat({
		"HTTP/1.1 101 Switching Protocols",
		"Upgrade: websocket",
		"Connection: Upgrade",
		"Sec-WebSocket-Accept: " .. accept,
		"",
		"",
	}, "\r\n")

	local done, err, rest = Handshake.parse_response(response, key)
	check(done and err == nil, "WS3 a valid accept validates")
	check(rest == "", "WS3 valid response leaves no bytes")

	local bad = response:gsub("Sec%-WebSocket%-Accept: [^\r]*", "Sec-WebSocket-Accept: AAAA", 1)
	local done2, err2 = Handshake.parse_response(bad, key)
	check(done2 and err2 ~= nil and err2:find("Sec%-WebSocket%-Accept") ~= nil, "WS3 a mismatched accept is rejected")

	local done3, err3 = Handshake.parse_response(response:gsub("101 Switching Protocols", "400 Bad Request"), key)
	check(done3 and err3 ~= nil and err3:find("rejected") ~= nil, "WS3 a non-101 status is rejected")

	local done4 = Handshake.parse_response("HTTP/1.1 101", key)
	check(done4 == false, "WS3 an incomplete response waits")
end

-- Continuation frames assemble into a single message; control frames pass through.
do
	local a = Assembler.new()
	check(
		a:process({ opcode = frame_codec.OPCODE.TEXT, payload = "hel", fin = false }) == nil,
		"WS4 a non-final frame yields nothing"
	)
	check(
		a:process({ opcode = frame_codec.OPCODE.CONTINUATION, payload = "lo", fin = true }) == "hello",
		"WS4 continuation frames assemble the message"
	)
	check(
		a:process({ opcode = frame_codec.OPCODE.TEXT, payload = "x", fin = true }) == "x",
		"WS4 a single frame returns directly"
	)
	check(
		a:process({ opcode = frame_codec.OPCODE.CLOSE, payload = "", fin = true }) == nil,
		"WS4 control frames yield nothing"
	)
end

-- HTTP response parsing: Content-Length framing, chunked arrival and EOF fallback.
do
	local raw = table.concat({
		"HTTP/1.1 201 Created",
		"Content-Type: application/json",
		"Content-Length: 5",
		"",
		"hello",
	}, "\r\n")

	local res, complete = HttpClient.parse_response(raw, false)
	check(res ~= nil and complete and res.status == 201 and res.body == "hello", "HTTP1 parses a content-length body")
	check(res ~= nil and res.headers["content-type"] == "application/json", "HTTP1 headers are lowercased")

	local _, incomplete = HttpClient.parse_response(raw:sub(1, 20), false)
	check(not incomplete, "HTTP1 a truncated body waits")

	local res2, complete2 = HttpClient.parse_response(raw, false)
	check(res2 ~= nil and complete2 and res2.body == "hello", "HTTP1 the full buffer completes")
end

do
	local raw = table.concat({ "HTTP/1.1 200 OK", "", "body" }, "\r\n")
	local _, complete = HttpClient.parse_response(raw, false)
	check(not complete, "HTTP2 without a length and not forced it waits")
	local res, complete2 = HttpClient.parse_response(raw, true)
	check(res ~= nil and complete2 and res.body == "body", "HTTP2 forced at EOF completes")
end

do
	local _, complete = HttpClient.parse_response("HTTP/1.1 200 OK\r\n", false)
	check(not complete, "HTTP3 without a header terminator it waits")
end
