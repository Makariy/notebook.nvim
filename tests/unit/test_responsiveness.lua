-- Tests stub the view's _editing method by assigning a field over it.
---@diagnostic disable:duplicate-set-field

local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local helpers = require("tests.helpers")

-- Responsiveness regressions: renders must not interrupt the user (cursor
-- jumps, buffers rewritten needlessly, the render pipeline getting stuck, or
-- kernel completion forcing a synchronous full-buffer rewrite).

---@param view NotebookView
---@param out_text string?
local function install_executer(view, out_text)
	out_text = out_text or "out\n"
	view.session.command_executer = {
		execute = function(_, _, opts)
			---@diagnostic disable-next-line:undefined-field
			local id = opts and opts.cell_id
			for _, c in ipairs(view.notebook.cells) do
				if c.metadata.id == id then
					c:add_output(Output.new({ output_type = "stream", name = "stdout", text = out_text }))
				end
			end
			vim.defer_fn(function()
				if opts and opts.on_done then
					opts.on_done("ok", 1)
				end
			end, 20)
			return "m"
		end,
	}
	function view.session:execute_cell(index)
		local cell = self.notebook:get(index)
		if not cell or not cell:is_code() then
			return
		end
		local id = cell.metadata.id
		self.command_executer:execute(cell.source, {
			cell_id = id,
			on_done = function(status, count)
				cell.execution_count = count
				self:_notify_done(id, status, count)
			end,
		})
	end
end

local function results(view)
	return table.concat(vim.api.nvim_buf_get_lines(view.results_buf, 0, -1, false), "|")
end

-- R1: kernel completion must not synchronously rebuild the buffers. It used to
-- call sync() inline, which rewrote the code/results buffers mid-action; it must
-- be deferred (debounced) instead.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local view = helpers.open_view(nb, "test_responsiveness.ipynb")
	vim.wait(30)
	install_executer(view)

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	view.controller:execute_current_cell()

	-- Enough time for on_done (20ms) to fire but not for the 50ms debounced render.
	vim.wait(30)
	check(results(view):find("out", 1, true) == nil, "R1 on_done defers the render (no synchronous buffer rewrite)")

	vim.wait(80)
	check(results(view):find("out", 1, true) ~= nil, "R1 deferred render eventually shows the output")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"R1 buffers aligned after deferred render"
	)
end

-- R2: re-rendering an unchanged model must not rewrite the results buffer.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local view = helpers.open_view(nb, "test_responsiveness.ipynb")
	vim.wait(30)

	view:render()
	local tick = vim.api.nvim_buf_get_changedtick(view.results_buf)
	view:render()
	check(
		vim.api.nvim_buf_get_changedtick(view.results_buf) == tick,
		"R2 no-op render does not rewrite the results buffer"
	)
end

-- R3: a render that fails must not leave the render pipeline stuck.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local view = helpers.open_view(nb, "test_responsiveness.ipynb")
	vim.wait(30)

	local broken = view.notebook.cells[1]
	broken.source = nil -- makes the layout build throw
	pcall(view.render, view)

	broken.source = "print('A')"
	table.insert(view.notebook.cells, Cell.code("print('B')"))
	view:render()
	local buf = table.concat(vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false), "|")
	check(buf:find("print('B')", 1, true) ~= nil, "R3 view renders again after a render error (_rendering not stuck)")
end

-- R4: a background render that inserts padding above the cursor must keep the
-- cursor on the same cell/source line (not leave it stranded on a shifted line).
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	local c2 = Cell.code("for i in range(3):\n    print(i)")
	c2.metadata.id = "c2"
	table.insert(nb.cells, c1)
	table.insert(nb.cells, c2)
	local view = helpers.open_view(nb, "test_responsiveness.ipynb")
	vim.wait(30)
	-- Cell 1 gains 3 output lines -> its block grows by 2 padding lines above cell 2.
	install_executer(view, "0\n1\n2\n")

	-- Trigger execution of cell 1, then park the cursor on cell 2's first source
	-- line before the deferred render fires (that render shifts cell 2 down).
	local start2 = view:get_cell_start(2)
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	view.controller:execute_current_cell()
	vim.api.nvim_win_set_cursor(view.code_win, { start2 + 2, 0 })
	local before = vim.api.nvim_win_get_cursor(view.code_win)

	vim.wait(100)

	local after = vim.api.nvim_win_get_cursor(view.code_win)
	-- Both cells still present, cell 2 shifted down by the new padding.
	local new_start2 = view:get_cell_start(2)
	check(new_start2 ~= nil and new_start2 == start2 + 2, "R4 cell 2 moved down by the added padding")
	check(after[1] == before[1] + 2, "R4 cursor followed its cell across the render")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"R4 buffers aligned"
	)
end

-- R5: while the user is editing (insert/replace mode) no render may fire: on_lines
-- skips editing-mode changes and the debounce drops a queued render, so the code
-- buffer is never rewritten between keystrokes. Leaving insert mode re-arms the
-- debounced render (that is the "stopped typing" trigger).
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local view = helpers.open_view(nb, "test_responsiveness.ipynb")
	vim.wait(30)

	local syncs = 0
	local orig = view.sync
	function view:sync(...)
		syncs = syncs + 1
		return orig(self, ...)
	end

	-- Simulate an active insert session (the predicate the scheduler consults).
	view._editing = function()
		return true
	end

	-- A buffer change while editing must not schedule a render.
	vim.api.nvim_buf_set_lines(view.code_buf, 3, 3, false, { "print('typing')" })
	vim.wait(80)
	check(syncs == 0, "R5 no render fires while editing (on_lines skips editing changes)")

	-- Even a directly-queued render is dropped while editing.
	view.scheduler:schedule()
	vim.wait(80)
	check(syncs == 0, "R5 no render fires from a queued schedule while editing")

	-- Revert the simulated typing; leaving insert mode re-arms the render.
	vim.api.nvim_buf_set_lines(view.code_buf, 3, 4, false, {})
	view._editing = function()
		return false
	end
	view.scheduler:schedule()
	vim.wait(80)
	check(syncs == 1, "R5 render fires after editing finishes")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"R5 buffers aligned after render"
	)
end

-- R6: render() itself refuses to run while editing (hard backstop on top of the
-- scheduler's is_editing check), so the code buffer is never rewritten mid-insert.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local view = helpers.open_view(nb, "test_responsiveness.ipynb")
	vim.wait(30)

	view._editing = function()
		return true
	end
	local before = vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false)
	view:render()
	local after = vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false)
	check(vim.deep_equal(before, after), "R6 render() is skipped while editing")

	view._editing = function()
		return false
	end
	view:render()
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"R6 render proceeds once editing ends"
	)
end
