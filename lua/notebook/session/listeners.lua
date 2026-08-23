---@class Listeners
---@field list SessionListener[]
local Listeners = {}
Listeners.__index = Listeners

---@return Listeners
function Listeners.new()
	return setmetatable({ list = {} }, Listeners)
end

---@param listener SessionListener
function Listeners:add(listener)
	table.insert(self.list, listener)
end

---@param event "on_progress" | "on_done" | "on_changed"
---@param ... any
function Listeners:emit(event, ...)
	for _, listener in ipairs(self.list) do
		local fn = listener[event]
		if fn then
			fn(...)
		end
	end
end

return Listeners
