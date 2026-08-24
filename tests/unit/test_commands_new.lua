local Notebook = require("notebook.notebook.notebook")
local Cell = require("notebook.notebook.cell")
local CellOutput = require("notebook.notebook.output")
local ExecutionState = require("notebook.notebook.execution_state")
local helpers = require("tests.helpers")

local function make_view()
	local nb = Notebook.new()
	table.insert(nb.cells, Cell.code("print(1)\nprint(2)\nprint(3)"))
	table.insert(nb.cells, Cell.markdown("Hello"))
	table.insert(nb.cells, Cell.code("print('err')"))
	table.insert(nb.cells, Cell.code("print('run')"))

	nb.cells[1].metadata.id = "c1"
	nb.cells[2].metadata.id = "c2"
	nb.cells[3].metadata.id = "c3"
	nb.cells[4].metadata.id = "c4"

	local view = helpers.open_view(nb, "test_new_cmds.ipynb")
	vim.wait(30)

	view.execution_state:set_done("c3", false)
	view.execution_state:set_busy("c4")

	return view
end

-- Test Split Cell
do
	local view = make_view()
	view:goto_cell(1)
	vim.api.nvim_win_set_cursor(view.code_win, { 4, 0 }) -- Cursor on "print(2)"
	view.controller:split_cell()

	check(#view.notebook.cells == 5, "SC1 splits the cell into two")
	check(view.notebook.cells[1].source == "print(1)", "SC2 first cell has the top half")
	check(view.notebook.cells[2].source == "print(2)\nprint(3)", "SC3 second cell has the bottom half")
	check(view:get_current_cell_index() == 2, "SC4 cursor moves to the newly created cell")
end

-- Test Join Cell
do
	local view = make_view()

	-- Join code with code
	view:goto_cell(3)
	view.controller:join_cell()
	check(#view.notebook.cells == 3, "JC1 successfully joined code cells")
	check(view.notebook.cells[3].source == "print('err')\nprint('run')", "JC2 source combined with double newline")

	-- Try to join code with markdown
	view:goto_cell(1)
	view.controller:join_cell()
	check(#view.notebook.cells == 3, "JC3 refused to join code with markdown")
end

-- Test GoToError and GoToRunning
do
	local view = make_view()
	view:goto_cell(1)

	view.controller:goto_error()
	check(view:get_current_cell_index() == 3, "GT1 goto_error jumps to the errored cell")

	view.controller:goto_running()
	check(view:get_current_cell_index() == 4, "GT2 goto_running jumps to the running cell")
end
