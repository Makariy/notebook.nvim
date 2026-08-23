local Cell = require("notebook.notebook.cell")

---@class CellClipboard
---@field cell? Cell The last copied cell (a detached snapshot)
local CellClipboard = {}
CellClipboard.__index = CellClipboard

---@return CellClipboard
function CellClipboard.new()
	return setmetatable({ cell = nil }, CellClipboard)
end

---@param cell Cell
function CellClipboard:copy(cell)
	self.cell = Cell.new({ cell_type = cell.cell_type, source = cell.source })
end

---@return Cell?
function CellClipboard:paste()
	local clip = self.cell
	if not clip then
		return nil
	end
	return Cell.new({ cell_type = clip.cell_type, source = clip.source })
end

---@return boolean
function CellClipboard:empty()
	return self.cell == nil
end

return CellClipboard
