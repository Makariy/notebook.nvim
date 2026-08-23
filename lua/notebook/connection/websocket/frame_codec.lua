local bit = require("bit")
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local rshift = bit.rshift

local M = {}

M.OPCODE = {
	CONTINUATION = 0x0,
	TEXT = 0x1,
	BINARY = 0x2,
	CLOSE = 0x8,
	PING = 0x9,
	PONG = 0xA,
}

---@param payload string
---@param opcode integer
---@return string
function M.encode(payload, opcode)
	payload = payload or ""
	local len = #payload

	local parts = {}
	parts[#parts + 1] = string.char(bor(0x80, band(opcode, 0x0f)))

	local MASK_BIT = 0x80
	if len < 126 then
		parts[#parts + 1] = string.char(bor(MASK_BIT, len))
	elseif len < 65536 then
		parts[#parts + 1] = string.char(bor(MASK_BIT, 126))
		parts[#parts + 1] = string.char(band(rshift(len, 8), 0xff), band(len, 0xff))
	else
		parts[#parts + 1] = string.char(bor(MASK_BIT, 127))
		for i = 7, 0, -1 do
			local shift = i * 8
			parts[#parts + 1] = string.char(shift >= 32 and 0 or band(rshift(len, shift), 0xff))
		end
	end

	local mask = {
		math.random(0, 255),
		math.random(0, 255),
		math.random(0, 255),
		math.random(0, 255),
	}
	parts[#parts + 1] = string.char(mask[1], mask[2], mask[3], mask[4])

	local masked = {}
	for i = 1, len do
		masked[i] = string.char(bxor(string.byte(payload, i), mask[((i - 1) % 4) + 1]))
	end
	parts[#parts + 1] = table.concat(masked)

	return table.concat(parts)
end

function M.try_parse(buf)
	if #buf < 2 then
		return nil, buf
	end

	local b1, b2 = string.byte(buf, 1, 2)
	local fin = band(b1, 0x80) ~= 0
	local opcode = band(b1, 0x0f)
	local masked = band(b2, 0x80) ~= 0
	local len = band(b2, 0x7f)

	local pos = 3
	if len == 126 then
		if #buf < pos + 1 then
			return nil, buf
		end
		local hi, lo = string.byte(buf, pos, pos + 1)
		len = hi * 256 + lo
		pos = pos + 2
	elseif len == 127 then
		if #buf < pos + 7 then
			return nil, buf
		end
		len = 0
		for i = 0, 7 do
			len = len * 256 + string.byte(buf, pos + i)
		end
		pos = pos + 8
	end

	local mask_key
	if masked then
		if #buf < pos + 3 then
			return nil, buf
		end
		mask_key = { string.byte(buf, pos, pos + 3) }
		pos = pos + 4
	end

	if #buf < pos + len - 1 then
		return nil, buf
	end

	local payload = buf:sub(pos, pos + len - 1)
	if masked then
		local unmasked = {}
		for i = 1, len do
			unmasked[i] = string.char(bxor(string.byte(payload, i), mask_key[((i - 1) % 4) + 1]))
		end
		payload = table.concat(unmasked)
	end

	return { fin = fin, opcode = opcode, payload = payload }, buf:sub(pos + len)
end

return M
