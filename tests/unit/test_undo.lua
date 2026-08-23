local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local NotebookSession = require("notebook.session.notebook_session")
local helpers = require("tests.helpers")

-- In headless mode consecutive buffer changes coalesce into a single undo
-- entry. Real users dispatch each command separately, so we force an undo
-- boundary by re-assigning 'undolevels' (which syncs the buffer) between the
-- simulated user actions.
---@param buf integer
local function undo_break(buf)
	local ul = vim.bo[buf].undolevels
	vim.bo[buf].undolevels = ul
end

-- Regression 1: re-executing a cell supersedes its in-flight execution, so
-- outputs are not duplicated.
do
	local nb = Notebook.new()
	table.insert(nb.cells, Cell.code("print('hello')"))
	local session = NotebookSession.new(nb)

	local done_count = 0
	session:subscribe({
		on_done = function()
			done_count = done_count + 1
		end,
	})

	local call = 0
	session.command_executer = {
		execute = function(_, _, dispatcher)
			call = call + 1
			local id = "m" .. call
			vim.defer_fn(function()
				if dispatcher.on_progress then
					dispatcher.on_progress({ type = "stream", name = "stdout", text = "out " .. call })
				end
			end, 50)
			vim.defer_fn(function()
				if dispatcher.on_done then
					dispatcher.on_done("ok", call)
				end
			end, 100)
			return id
		end,
	}

	session:execute_cell(1)
	vim.defer_fn(function()
		session:execute_cell(1)
	end, 20)
	vim.wait(300)

	check(#nb.cells[1].outputs == 1, "double execute keeps a single output set")
	check(done_count == 1, "double execute emits a single done event")
	check(nb.cells[1].execution_count == 2, "latest execution count wins")
end

-- Regression 7: decoration-only renders (padding rebalancing, marker id
-- injection) add no undo entry, so native `u` always lands on a real change.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	c1:add_output(Output.new({ output_type = "stream", name = "stdout", text = "l1\nl2\nl3" }))
	table.insert(nb.cells, c1)

	local view = require("tests.helpers").open_view(nb, "test_undo.ipynb")
	vim.wait(30)

	local function seq()
		return vim.fn.undotree(view.code_buf).seq_last
	end

	-- Typing creates exactly one undo entry; the InsertLeave render merges its
	-- decoration into it via :undojoin.
	local before = seq()
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 2, 0 })
	vim.fn.feedkeys("oprint('B')\x1b", "xt")
	vim.wait(150)
	check(seq() == before + 1, "typing adds a single undo entry")

	-- Growing the output rebalances padding only: no new undo entry.
	table.insert(c1.outputs, Output.new({ output_type = "stream", name = "stdout", text = "more\nmore\nmore\nmore" }))
	view:render()
	vim.wait(30)
	check(seq() == before + 1, "a decoration render adds no undo entry")
end

-- Regression 2: undo after "delete -> execute -> undo" must restore the deleted
-- cell and leave the executed cell in "success", never stranded in "Running".
do
	local nb = Notebook.new()
	table.insert(nb.cells, Cell.code("print('A')"))
	table.insert(nb.cells, Cell.code("print('B')"))
	table.insert(nb.cells, Cell.code("print('C')"))

	local view = require("tests.helpers").open_view(nb, "test_undo.ipynb")

	view.session.command_executer = {
		execute = function(_, code, opts)
			for _, c in ipairs(view.notebook.cells) do
				if c.cell_type == "code" and c.source == code then
					c:add_output(Output.new({ output_type = "stream", name = "stdout", text = "l1\nl2\nl3" }))
				end
			end
			vim.defer_fn(function()
				if opts and opts.on_done then
					opts.on_done("ok", 1)
				end
			end, 100)
		end,
	}

	view.controller:delete_cell()
	undo_break(view.code_buf)
	view.controller:execute_current_cell()
	undo_break(view.code_buf)
	vim.wait(200) -- let the kernel finish (success + output padding)

	helpers.undo(view.code_buf)
	view:sync()

	local sources = {}
	local state_by_source = {}
	for _, c in ipairs(view.notebook.cells) do
		sources[c.source] = true
		local entry = view.execution_state:get(c.metadata.id)
		state_by_source[c.source] = entry and entry.state or nil
	end

	check(#view.notebook.cells == 3, "deleted cell restored after undo")
	check(sources["print('A')"] == true, "restored cell A present")
	check(state_by_source["print('B')"] == "success", "executed cell stays success, not Running")
end

-- Regression 3: typing a line manually must undo as a whole line and redo as a
-- whole line. The render pipeline is event-driven (it fires on InsertLeave/
-- commands, never mid-insert), so the code buffer is not rewritten between
-- keystrokes and the typed line stays a single undo entry. A single `u` removes
-- the whole line and a single `<C-r>` restores it.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)

	local view = require("tests.helpers").open_view(nb, "test_undo.ipynb")
	vim.wait(30)

	local function buffer(view)
		return table.concat(vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false), "\n")
	end

	-- Type a new line into the cell (real insert session), then leave insert mode.
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 2, 0 })
	vim.fn.feedkeys("oprint('B')\x1b", "xt")
	vim.wait(150)

	check(buffer(view):find("print('B')", 1, true) ~= nil, "typed line is in the buffer")

	-- One undo removes the ENTIRE typed line, not just the last character.
	vim.cmd("normal! u")
	vim.wait(100)
	check(buffer(view):find("print('B')", 1, true) == nil, "undo removes the whole typed line")
	check(buffer(view):find("print('A')", 1, true) ~= nil, "original source survives the undo")

	-- One redo restores the ENTIRE typed line, not just the last character.
	vim.cmd("normal! \x12")
	vim.wait(100)
	check(buffer(view):find("print('B')", 1, true) ~= nil, "redo restores the whole typed line")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers aligned after redo"
	)

	-- A second undo removes the line again: we are back at the user's baseline.
	vim.cmd("normal! u")
	vim.wait(100)
	check(buffer(view):find("print('B')", 1, true) == nil, "second undo removes the line again")
	check(buffer(view):find("print('A')", 1, true) ~= nil, "second undo leaves the baseline intact")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers aligned after undo"
	)
end

-- Regression 4: typing a line and leaving a trailing blank (Enter before Esc)
-- must still undo as a whole line. The render strips the trailing blank on
-- InsertLeave (a decoration write the undo logic skips), but the typed content
-- is reverted in one step.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)

	local view = require("tests.helpers").open_view(nb, "test_undo.ipynb")
	vim.wait(30)

	local function buffer(view)
		return table.concat(vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false), "\n")
	end

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 2, 0 })
	vim.fn.feedkeys("oprint('B')\r\x1b", "xt")
	vim.wait(150)

	check(buffer(view):find("print('B')", 1, true) ~= nil, "typed line is in the buffer (with trailing blank)")

	vim.cmd("normal! u")
	vim.wait(100)
	check(buffer(view):find("print('B')", 1, true) == nil, "undo removes the whole typed line (trailing blank case)")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers aligned after undo (trailing blank case)"
	)
end

-- Regression 5: typing into a cell that has output padding must undo as a whole
-- line. The InsertLeave render rebalances padding (block height changes), which
-- rewrites the buffer — that decoration write is skipped by undo, so `u` still
-- removes the whole typed line.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	c1:add_output(Output.new({ output_type = "stream", name = "stdout", text = "l1\nl2\nl3" }))
	table.insert(nb.cells, c1)

	local view = require("tests.helpers").open_view(nb, "test_undo.ipynb")
	vim.wait(30)

	local function buffer(view)
		return table.concat(vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false), "\n")
	end

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 2, 0 })
	vim.fn.feedkeys("oprint('B')\x1b", "xt")
	vim.wait(150)

	check(buffer(view):find("print('B')", 1, true) ~= nil, "typed line is in the buffer (with output padding)")

	vim.cmd("normal! u")
	vim.wait(100)
	check(buffer(view):find("print('B')", 1, true) == nil, "undo removes the whole typed line (output padding case)")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers aligned after undo (output padding case)"
	)
end

-- Regression 6: typing a bare "# %%" marker (which creates a new cell) must undo
-- as a whole line too. The render injects a freshly generated id into the marker,
-- but the fingerprint treats cell ids as metadata, so that id-injection write is
-- skipped and one `u` removes the marker the user actually typed (no id churn).
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)

	local view = require("tests.helpers").open_view(nb, "test_undo.ipynb")
	vim.wait(30)

	local function markers(view)
		local n = 0
		for _, l in ipairs(vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false)) do
			if l:match("^# %%%% %[code:") then
				n = n + 1
			end
		end
		return n
	end

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 2, 0 })
	vim.fn.feedkeys("o# %%\x1b", "xt")
	vim.wait(150)

	-- The bare marker became a real cell marker (2 cells now).
	check(markers(view) == 2, "bare marker becomes a new cell")

	vim.cmd("normal! u")
	vim.wait(100)
	check(markers(view) == 1, "undo removes the typed marker line")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers aligned after undo (marker case)"
	)
end
