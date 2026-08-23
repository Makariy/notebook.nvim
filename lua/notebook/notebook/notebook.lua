---@class Notebook
---@field cells Cell[]
---@field metadata table
---@field nbformat integer
---@field nbformat_minor integer
local Notebook = {}
Notebook.__index = Notebook

---@param cells? Cell[]
---@param opts? { metadata?: table, nbformat?: integer, nbformat_minor?: integer }
---@return Notebook
function Notebook.new(cells, opts)
	opts = opts or {}
	local self = setmetatable({}, Notebook)
	self.cells = cells or {}
	self.metadata = opts.metadata or {}
	self.nbformat = opts.nbformat or 4
	self.nbformat_minor = opts.nbformat_minor or 0
	return self
end

---@param index integer
---@return Cell?
function Notebook:get(index)
	return self.cells[index]
end

---@param cell Cell
---@param index? integer
function Notebook:insert(cell, index)
	table.insert(self.cells, index or (#self.cells + 1), cell)
end

---@param index integer
---@return Cell?
function Notebook:remove(index)
	return table.remove(self.cells, index)
end

return Notebook
