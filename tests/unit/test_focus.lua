local config = require("notebook.config")
local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local helpers = require("tests.helpers")

local DEFAULT = {
	keymaps = { next_cell = "]c", previous_cell = "[c", focus = false },
}

local function restore_config()
	config.setup(DEFAULT)
end

---@param id string
---@param source string
---@return Cell
local function code_cell(id, source)
	local c = Cell.code(source)
	c.metadata.id = id
	return c
end

restore_config()

local function make_view()
	local nb = Notebook.new()
	table.insert(nb.cells, code_cell("c1", "x = 1\nprint(x)"))
	table.insert(nb.cells, code_cell("c2", "y = 2"))
	local view = helpers.open_view(nb, "test_focus.ipynb")
	vim.wait(30)
	return view
end

-- Code-focus hides the results window, wraps the code window, and keeps the
-- results buffer alive (bufhidden=hide) so the notebook stays in sync.
do
	local view = make_view()
	local code_lines = vim.api.nvim_buf_line_count(view.code_buf)
	local res_lines = vim.api.nvim_buf_line_count(view.results_buf)

	view.focus_mode:toggle("code")

	check(not vim.api.nvim_win_is_valid(view.results_win), "F1 code-focus closes the results window")
	check(vim.api.nvim_win_is_valid(view.code_win), "F1 code window stays open")
	check(vim.wo[view.code_win].wrap, "F1 code window wraps while focused")
	check(vim.api.nvim_buf_is_valid(view.results_buf), "F1 results buffer survives hiding")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == code_lines
			and vim.api.nvim_buf_line_count(view.results_buf) == res_lines,
		"F1 buffers keep their layout while focused"
	)
	check(view.focus_mode:active(), "F1 focus mode reports active")

	-- A render while focused must not error.
	local ok = pcall(function()
		view:render()
	end)
	check(ok, "F1 render works with a single pane")

	view.focus_mode:toggle("code")
	check(vim.api.nvim_win_is_valid(view.results_win), "F1 toggling again restores the results window")
	check(vim.api.nvim_win_is_valid(view.code_win), "F1 code window still valid")
	check(not vim.wo[view.code_win].wrap, "F1 code window unwrapped after exit")
	check(not vim.wo[view.results_win].wrap, "F1 results window unwrapped after exit")
	check(vim.wo[view.code_win].scrollbind and vim.wo[view.results_win].scrollbind, "F1 scroll binding restored")
	check(not view.focus_mode:active(), "F1 focus mode inactive after exit")
end

-- Output-focus hides the code window and wraps the results window; cell
-- navigation keeps working through the remaining window.
do
	local view = make_view()
	view.focus_mode:toggle("output")

	check(not vim.api.nvim_win_is_valid(view.code_win), "F2 output-focus closes the code window")
	check(vim.api.nvim_win_is_valid(view.results_win), "F2 results window stays open")
	check(vim.wo[view.results_win].wrap, "F2 results window wraps while focused")
	check(vim.api.nvim_buf_is_valid(view.code_buf), "F2 code buffer survives hiding")

	view:goto_cell(2)
	check(
		vim.api.nvim_win_get_cursor(view.results_win)[1] == view:get_cell_start(2) + 1,
		"F2 cell navigation works through the results window"
	)

	view.focus_mode:toggle("output")
	check(vim.api.nvim_win_is_valid(view.code_win), "F2 toggling again restores the code window")
	check(vim.api.nvim_win_is_valid(view.results_win), "F2 results window still valid")
	check(not vim.wo[view.code_win].wrap and not vim.wo[view.results_win].wrap, "F2 both windows unwrapped after exit")
end

-- Switching panes normalizes through the split and lands on the new pane.
do
	local view = make_view()
	view.focus_mode:toggle("code")
	view.focus_mode:toggle("output")

	check(not vim.api.nvim_win_is_valid(view.code_win), "F3 switching to output-focus hides the code window")
	check(vim.api.nvim_win_is_valid(view.results_win), "F3 switching to output-focus keeps the results window")
	check(vim.wo[view.results_win].wrap, "F3 switched pane wraps")
end

-- Entering code-focus hides the images that live in the results window.
do
	local view = make_view()
	local hidden = false
	local orig = view.image_renderer.hide_all
	view.image_renderer.hide_all = function(...)
		hidden = true
		return orig(view.image_renderer, ...)
	end
	view.focus_mode:toggle("code")
	check(hidden, "F4 images hidden when the results window closes")
end

-- The controller and the :NotebookFocus command reach FocusMode.
do
	local view = make_view()
	view.controller:focus("code")
	check(not vim.api.nvim_win_is_valid(view.results_win), "F5 controller:focus enters code-focus")
	view.controller:focus("")
	check(vim.api.nvim_win_is_valid(view.results_win), "F5 controller:focus with no pane restores the split")

	local commands = vim.api.nvim_get_commands({})
	check(commands["NotebookFocus"] ~= nil, "F5 :NotebookFocus is registered")
	check(commands["NotebookFocus"].nargs == "?", "F5 :NotebookFocus accepts an optional pane argument")
end

-- Commands resolve through the results window too, so :Notebook* works while
-- output-focus makes the results buffer current.
do
	local view = make_view()
	local notebook = require("notebook")
	notebook.views[view.code_buf] = view
	view.focus_mode:toggle("output")
	check(vim.api.nvim_get_current_buf() == view.results_buf, "F7 output-focus leaves the results buffer current")
	check(notebook.current_view() == view, "F7 commands resolve from the results window")
	notebook.views[view.code_buf] = nil
end

-- No-arg focus targets the pane the cursor is currently in, not always code.
do
	local view = make_view()
	vim.api.nvim_set_current_win(view.results_win)
	view.controller:focus("")
	check(not vim.api.nvim_win_is_valid(view.code_win), "F9 no-arg focus from the results pane enters output-focus")

	view.controller:focus("")
	check(vim.api.nvim_win_is_valid(view.code_win), "F9 no-arg focus again restores the split")
end

-- Exiting code-focus re-resolves images against the recreated results window.
-- Regression: images bound to the closed window kept their stale window handle,
-- so image.nvim never re-rendered them after the split came back.
do
	local view = make_view()
	local real_available = view.image_renderer.available
	view.image_renderer.available = function()
		return true
	end
	view.focus_mode:toggle("code")
	local gen_after_enter = view.image_renderer._generation
	view.focus_mode:toggle("code")
	check(view.image_renderer._generation > gen_after_enter, "F8 exiting code-focus bumps the image window generation")
	check(view.image_renderer._window == view.results_win, "F8 images re-bound to the recreated results window")
	view.image_renderer.available = real_available
end

-- The configured focus keymap is bound to the code buffer.
do
	config.setup({ keymaps = { focus = "<Leader>nf" } })
	local view = make_view()
	local lhs = vim.api.nvim_replace_termcodes("<Leader>nf", true, false, true)
	local mapping = vim.fn.maparg(lhs, "n", false, true)
	check(type(mapping) == "table" and mapping.desc == "Toggle wrapped code focus", "F6 focus keymap is bound")
	restore_config()
end
