local CellClipboard = require("notebook.ui.cell_clipboard")
local Cell = require("notebook.notebook.cell")

do
	local cb = CellClipboard.new()
	check(cb:empty(), "CL1 clipboard starts empty")
	check(cb:paste() == nil, "CL1 pasting an empty clipboard returns nil")

	local cell = Cell.new({ cell_type = "code", source = "x = 1" })
	cb:copy(cell)
	check(not cb:empty(), "CL2 clipboard holds a cell after copy")

	local pasted = cb:paste()
	check(pasted.cell_type == "code" and pasted.source == "x = 1", "CL3 paste returns a cell with the copied source")
	check(pasted ~= cell, "CL4 paste returns a fresh object (no aliasing)")

	-- Mutating a pasted cell must not affect the clipboard.
	pasted.source = "y = 2"
	check(cb:paste().source == "x = 1", "CL5 clipboard unaffected by mutating a pasted cell")
	check(cell.source == "x = 1", "CL5 original cell unaffected by the paste")
end

do
	-- A markdown cell round-trips through the clipboard too.
	local cb = CellClipboard.new()
	local md = Cell.new({ cell_type = "markdown", source = "# title" })
	cb:copy(md)
	check(cb:paste().cell_type == "markdown", "CL6 markdown cell copies with its type")
end
