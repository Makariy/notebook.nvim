local frame_codec = require("notebook.connection.websocket.frame_codec")

---@class MessageAssembler
---@field fragments string[]
local MessageAssembler = {}
MessageAssembler.__index = MessageAssembler

function MessageAssembler.new()
	return setmetatable({ fragments = {} }, MessageAssembler)
end

---@param frame table
---@return string?
function MessageAssembler:process(frame)
	if
		frame.opcode == frame_codec.OPCODE.TEXT
		or frame.opcode == frame_codec.OPCODE.BINARY
		or frame.opcode == frame_codec.OPCODE.CONTINUATION
	then
		table.insert(self.fragments, frame.payload)

		if frame.fin then
			local msg = table.concat(self.fragments)
			self.fragments = {}
			return msg
		end
	end
	return nil
end

return MessageAssembler
