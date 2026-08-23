---@class RenderScheduler
---@field on_render fun()
---@field is_editing? fun(): boolean
---@field pending boolean
---@field in_render boolean
local RenderScheduler = {}
RenderScheduler.__index = RenderScheduler

local DEBOUNCE_MS = 50

---@param on_render fun() Debounced callback that performs the actual re-render.
---@param is_editing? fun(): boolean
---@return RenderScheduler
function RenderScheduler.new(on_render, is_editing)
	return setmetatable({
		on_render = on_render,
		is_editing = is_editing,
		pending = false,
		in_render = false,
	}, RenderScheduler)
end

function RenderScheduler:begin_render()
	self.in_render = true
end

function RenderScheduler:end_render()
	self.in_render = false
end

function RenderScheduler:schedule()
	if self.in_render or self.pending then
		return
	end
	self.pending = true
	vim.defer_fn(function()
		self.pending = false
		if self.is_editing and self.is_editing() then
			return
		end
		self.on_render()
	end, DEBOUNCE_MS)
end

---@param code_buf integer
function RenderScheduler:attach(code_buf)
	vim.api.nvim_buf_attach(code_buf, false, {
		on_lines = function()
			if self.in_render then
				return
			end
			if self.is_editing and self.is_editing() then
				return
			end
			self:schedule()
		end,
	})
end

return RenderScheduler
