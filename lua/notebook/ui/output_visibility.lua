---@class OutputVisibility
---@field hidden table<string, boolean> Cell ids whose outputs are hidden
local OutputVisibility = {}
OutputVisibility.__index = OutputVisibility

---@return OutputVisibility
function OutputVisibility.new()
	return setmetatable({ hidden = {} }, OutputVisibility)
end

---@return table<string, boolean> The live set of hidden cell ids
function OutputVisibility:state()
	return self.hidden
end

---@param cell_id string
function OutputVisibility:toggle(cell_id)
	if self.hidden[cell_id] then
		self.hidden[cell_id] = nil
	else
		self.hidden[cell_id] = true
	end
end

---Hide every code cell's outputs, or reveal all when anything is hidden.
---@param notebook Notebook
function OutputVisibility:toggle_all(notebook)
	if next(self.hidden) then
		self.hidden = {}
		return
	end

	self.hidden = {}
	for _, cell in ipairs(notebook.cells) do
		if cell.cell_type == "code" and cell.metadata.id then
			self.hidden[cell.metadata.id] = true
		end
	end
end

return OutputVisibility
