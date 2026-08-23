local config = require("notebook.config")
local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local helpers = require("tests.helpers")

local DEFAULT = {
	keymaps = { next_cell = "]c", previous_cell = "[c" },
}

local function restore()
	config.setup(DEFAULT)
end

-- Defaults.
do
	restore()
	local c = config.get()
	check(c.keymaps.next_cell == "]c" and c.keymaps.previous_cell == "[c", "C1 default cell-jump keymaps")
end

-- setup() merges overrides and keeps unspecified defaults.
do
	config.setup({ keymaps = { next_cell = "]m" } })
	local c = config.get()
	check(c.keymaps.next_cell == "]m", "C2 setup overrides next_cell")
	check(c.keymaps.previous_cell == "[c", "C2 unspecified previous_cell keeps its default")
	restore()
end

-- A mapping can be disabled with false.
do
	config.setup({ keymaps = { next_cell = false } })
	check(config.get().keymaps.next_cell == false, "C3 a keymap can be disabled with false")
	restore()
end

-- Cell jumping: goto_cell() and the configured mappings.
do
	restore()
	local nb = Notebook.new()
	for i = 1, 3 do
		local c = Cell.code("x = " .. i)
		c.metadata.id = "c" .. i
		table.insert(nb.cells, c)
	end
	local view = helpers.open_view(nb, "test_config.ipynb")
	vim.wait(30)

	view:goto_cell(2)
	check(
		vim.api.nvim_win_get_cursor(view.code_win)[1] == view:get_cell_start(2) + 1,
		"C4 goto_cell lands on the cell marker"
	)

	vim.api.nvim_feedkeys("]c", "x", false)
	vim.wait(10)
	check(
		vim.api.nvim_win_get_cursor(view.code_win)[1] == view:get_cell_start(3) + 1,
		"C4 ]c jumps to the next cell marker"
	)

	vim.api.nvim_feedkeys("[c", "x", false)
	vim.wait(10)
	check(
		vim.api.nvim_win_get_cursor(view.code_win)[1] == view:get_cell_start(2) + 1,
		"C4 [c jumps to the previous cell marker"
	)

	vim.api.nvim_feedkeys("]c", "x", false)
	vim.wait(10)
	check(
		vim.api.nvim_win_get_cursor(view.code_win)[1] == view:get_cell_start(3) + 1,
		"C4 ]c at the last cell is a no-op"
	)

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	vim.api.nvim_feedkeys("2]c", "x", false)
	vim.wait(10)
	check(vim.api.nvim_win_get_cursor(view.code_win)[1] == view:get_cell_start(3) + 1, "C4 a count jumps several cells")
end

-- Custom keymaps take effect; disabled keymaps are not bound.
do
	config.setup({ keymaps = { next_cell = "]n", previous_cell = false } })
	local nb = Notebook.new()
	local c1 = Cell.code("x = 1")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local c2 = Cell.code("x = 2")
	c2.metadata.id = "c2"
	table.insert(nb.cells, c2)
	local view = helpers.open_view(nb, "test_config.ipynb")
	vim.wait(30)

	local maparg_next = vim.fn.maparg("]n", "n", false, true)
	check(maparg_next ~= "" and maparg_next.desc == "Jump to next cell marker", "C5 custom next_cell mapping is bound")
	local prev = vim.fn.maparg("[c", "n", false, true)
	local prev_desc = type(prev) == "table" and prev.desc or ""
	check(prev_desc ~= "Jump to previous cell marker", "C5 a disabled mapping is not bound by the plugin")

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	vim.api.nvim_feedkeys("]n", "x", false)
	vim.wait(10)
	check(
		vim.api.nvim_win_get_cursor(view.code_win)[1] == view:get_cell_start(2) + 1,
		"C5 custom mapping jumps to the next cell"
	)
	restore()
end
