local Saver = require("notebook.ui.notebook_saver")
local Notebook = require("notebook.notebook.notebook")
local Cell = require("notebook.notebook.cell")

do
	local nb = Notebook.new()
	local c = Cell.code("print('save')")
	c.metadata.id = "s1"
	table.insert(nb.cells, c)

	-- Write into the platform temp dir, never the working tree.
	local path = vim.fn.tempname() .. ".ipynb"
	local ok = Saver.save(path, nb)
	check(ok, "S1 save returns true on success")
	local f = io.open(path, "r")
	check(f ~= nil, "S1 saved file exists")
	if f then
		local json = f:read("a")
		f:close()
		os.remove(path)
		check(json:find("print%('save'%)") ~= nil, "S1 json contains the cell source")
	end
end
