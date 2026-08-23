local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local helpers = require("tests.helpers")

-- Issue 1: renders that do not change the results buffer must not touch images.
-- Every render used to clear_extmarks() + sync() unconditionally, which flashed
-- images on the terminal (the kitty backend draws immediately) during undo/redo.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')\nprint('B')\nprint('C')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)

	local view = helpers.open_view(nb, "test_gating.ipynb")
	vim.wait(30)

	local cleared = 0
	local last_force = nil
	view.image_renderer = {
		available = function()
			return true
		end,
		resolve = function()
			return {}
		end,
		clear_extmarks = function()
			cleared = cleared + 1
		end,
		sync = function(_, _, _, force)
			last_force = force
		end,
	}

	view:render()
	check(cleared == 0, "G1 a no-op render never clears images")
	check(last_force == false, "G1 a no-op render does not force a redraw")

	c1:add_output(Output.new({ output_type = "stream", name = "stdout", text = "out" }))
	view:render()
	check(cleared == 1, "G2 a results-changing render clears images once")
	check(last_force == true, "G2 a results-changing render forces a redraw")

	view:render()
	check(cleared == 1, "G3 further no-op renders stay quiet")
end
