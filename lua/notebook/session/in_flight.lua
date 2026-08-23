---@class InFlight
---@field executing table<string, string>
---@field waiting table<string, boolean>
local InFlight = {}
InFlight.__index = InFlight

---@return InFlight
function InFlight.new()
	return setmetatable({ executing = {}, waiting = {} }, InFlight)
end

---@param cell_id string
---@param msg_id string
function InFlight:begin(cell_id, msg_id)
	self.executing[cell_id] = msg_id
end

---@param cell_id string
---@param msg_id string
---@return boolean
function InFlight:is_current(cell_id, msg_id)
	return self.executing[cell_id] == msg_id
end

---@param cell_id string
---@return boolean Whether output should be held back while waiting for a clear.
function InFlight:is_waiting(cell_id)
	return self.waiting[cell_id] == true
end

---@param cell_id string
---@param wait boolean
function InFlight:set_waiting(cell_id, wait)
	self.waiting[cell_id] = wait
end

---@param cell_id string
function InFlight:finish(cell_id)
	self.executing[cell_id] = nil
	self.waiting[cell_id] = nil
end

return InFlight
