local Cell = require("notebook.notebook.cell")

local M = {}

---@param notebook Notebook
---@param specs CellSpec[]
---@param graveyard? table<string, Cell>
---@return Notebook
function M.reconcile(notebook, specs, graveyard)
	graveyard = graveyard or {}

	local by_id = {}
	for _, cell in ipairs(notebook.cells) do
		if cell.metadata.id then
			by_id[cell.metadata.id] = cell
		end
	end
	for id, cell in pairs(graveyard) do
		by_id[id] = cell
	end

	local new_cells = {}
	for _, spec in ipairs(specs) do
		local existing = spec.id and by_id[spec.id]
		if existing then
			existing.source = spec.source
			existing.cell_type = spec.cell_type
			existing.metadata.id = spec.id
			graveyard[spec.id] = nil
			table.insert(new_cells, existing)
		else
			table.insert(
				new_cells,
				Cell.new({
					cell_type = spec.cell_type,
					source = spec.source,
					metadata = { id = spec.id },
				})
			)
		end
	end

	local active = {}
	for _, cell in ipairs(new_cells) do
		active[cell.metadata.id] = true
	end
	for _, cell in ipairs(notebook.cells) do
		if cell.metadata.id and not active[cell.metadata.id] then
			graveyard[cell.metadata.id] = cell
		end
	end

	notebook.cells = new_cells
	return notebook
end

return M
