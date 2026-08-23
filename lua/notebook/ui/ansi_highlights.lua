---@class HighlightRegistry
---@field _counter integer
---@field _cache table<string, string>
local HighlightRegistry = {}
HighlightRegistry.__index = HighlightRegistry

local BASE_COLORS = {
	[0] = "#000000",
	[1] = "#cd0000",
	[2] = "#00cd00",
	[3] = "#cdcd00",
	[4] = "#0000ee",
	[5] = "#cd00cd",
	[6] = "#00cdcd",
	[7] = "#e5e5e5",
	[8] = "#7f7f7f",
	[9] = "#ff0000",
	[10] = "#00ff00",
	[11] = "#ffff00",
	[12] = "#5c5cff",
	[13] = "#ff00ff",
	[14] = "#00ffff",
	[15] = "#ffffff",
}

---@private Prefer the terminal's real palette when Neovim exposes it.
---@param idx integer
---@return string
local function ansi_color(idx)
	local v = vim.g["terminal_color_" .. idx]
	if type(v) == "string" and v:match("^#%x%x%x%x%x%x$") then
		return v
	end
	return BASE_COLORS[idx] or "#ffffff"
end

---@return HighlightRegistry
function HighlightRegistry.new()
	local self = setmetatable({}, HighlightRegistry)
	self._counter = 0
	self._cache = {}
	return self
end

---@param fg integer?
---@param bg integer?
---@param bold boolean
---@param italic boolean
---@param underline boolean
---@return string
function HighlightRegistry:group(fg, bg, bold, italic, underline)
	local key =
		string.format("%s|%s|%s|%s|%s", fg or "-", bg or "-", bold and 1 or 0, italic and 1 or 0, underline and 1 or 0)
	local name = self._cache[key]
	if not name then
		self._counter = self._counter + 1
		name = "NotebookAnsi" .. self._counter
		self._cache[key] = name
		local attrs = {}
		if fg then
			attrs.fg = ansi_color(fg)
		end
		if bg then
			attrs.bg = ansi_color(bg)
		end
		if bold then
			attrs.bold = true
		end
		if italic then
			attrs.italic = true
		end
		if underline then
			attrs.underline = true
		end
		vim.api.nvim_set_hl(0, name, attrs)
	end
	return name
end

return HighlightRegistry
