---@class EditMode
---@field _editing boolean
local EditMode = {}
EditMode.__index = EditMode

---@return EditMode
function EditMode.new()
	return setmetatable({ _editing = false }, EditMode)
end

function EditMode:begin()
	self._editing = true
end

function EditMode:finish()
	self._editing = false
end

---@return boolean Whether the user is currently editing and renders must wait.
function EditMode:active()
	if self._editing then
		return true
	end
	return vim.api.nvim_get_mode().mode:match("^[iR]") ~= nil
end

return EditMode
