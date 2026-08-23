---@class ExecutionEntry
---@field state? "busy" | "success" | "error" (nil while a fresh entry is being filled in)
---@field start_time? integer nanoseconds (vim.uv.hrtime)
---@field end_time? integer nanoseconds

---@class ExecutionState
---@field entries table<string, ExecutionEntry>
local ExecutionState = {}
ExecutionState.__index = ExecutionState

---@return ExecutionState
function ExecutionState.new()
	return setmetatable({ entries = {} }, ExecutionState)
end

---@param cell_id string
function ExecutionState:set_busy(cell_id)
	self.entries[cell_id] = { state = "busy", start_time = vim.uv.hrtime(), end_time = nil }
end

---@param cell_id string
---@param ok boolean
function ExecutionState:set_done(cell_id, ok)
	local entry = self.entries[cell_id]
	if not entry then
		entry = {}
		self.entries[cell_id] = entry
	end
	entry.state = ok and "success" or "error"
	entry.end_time = vim.uv.hrtime()
end

---@return boolean changed whether any cell changed
function ExecutionState:set_error_busy()
	local changed = false
	for _, entry in pairs(self.entries) do
		if entry.state == "busy" then
			entry.state = "error"
			changed = true
		end
	end
	return changed
end

---@param cell_id string
---@return ExecutionEntry?
function ExecutionState:get(cell_id)
	return self.entries[cell_id]
end

return ExecutionState
