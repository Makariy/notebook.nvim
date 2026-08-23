local M = require("notebook")

-- M.open must not conflate "path does not exist" (fresh notebook) with "path
-- exists but cannot be opened as a notebook" (a real error that would silently
-- overwrite the file with an empty model on the next save).
do
	local missing = "/tmp/opencode/nbdiag/definitely-missing.ipynb"
	vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	local view = M.open(missing)
	check(view ~= nil, "O1 opening a missing file creates a view")
	if not view then
		return
	end
	check(#view.notebook.cells == 1 and view.notebook.cells[1].source == "", "O1 fresh notebook has one empty cell")
end

do
	local dir = "/tmp/opencode/nbdiag"
	vim.fn.mkdir(dir, "p")
	vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	local view = M.open(dir)
	check(view == nil, "O2 opening a directory returns no view")
end

do
	local path = "/tmp/opencode/nbdiag/garbage.ipynb"
	local f = assert(io.open(path, "w"))
	f:write("this is not json")
	f:close()
	vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	local view = M.open(path)
	check(view == nil, "O3 malformed json returns no view")
	os.remove(path)
end

do
	local path = "/tmp/opencode/nbdiag/valid.ipynb"
	local f = assert(io.open(path, "w"))
	f:write(vim.json.encode({ cells = {}, nbformat = 4, nbformat_minor = 5 }))
	f:close()
	vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	local view = M.open(path)
	check(view ~= nil, "O4 a valid notebook opens")
	if not view then
		return
	end
	check(#view.notebook.cells == 0, "O4 an empty notebook has no cells")
	os.remove(path)
end
