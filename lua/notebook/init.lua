local IpynbParser = require("notebook.notebook.ipynb_parser")
local NotebookView = require("notebook.ui.notebook_view")
local config = require("notebook.config")

local M = {}

---@type table<integer, NotebookView>
M.views = {}

---@private
---@param path string
---@return string? content, string? err io.open error (nil when the file opened)
local function read_file(path)
	local f, err = io.open(path, "rb")
	if not f then
		return nil, err
	end
	local content = f:read("*a")
	f:close()
	return content, nil
end

---@private
---@param notebook Notebook
---@param path string
---@return NotebookView
local function open_view(notebook, path)
	local view = NotebookView.new(notebook, path)
	view:open()
	M.views[view.code_buf] = view
	return view
end

---@private
---@return Notebook
local function empty_notebook()
	local Notebook = require("notebook.notebook.notebook")
	local Cell = require("notebook.notebook.cell")
	local nb = Notebook.new()
	table.insert(nb.cells, Cell.code(""))
	return nb
end

---@param path string
---@return NotebookView?
function M.open(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then
		return open_view(empty_notebook(), path)
	end
	if stat.type ~= "file" then
		vim.notify("Could not read " .. path .. ": not a regular file", vim.log.levels.ERROR)
		return nil
	end

	local content, read_err = read_file(path)
	if read_err then
		vim.notify("Could not read " .. path .. ": " .. tostring(read_err), vim.log.levels.ERROR)
		return nil
	end
	content = content or ""
	if content:match("^%s*$") then
		return open_view(empty_notebook(), path)
	end

	local notebook, err = IpynbParser.parse(content)
	if not notebook then
		vim.notify("Could not parse " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end

	return open_view(notebook, path)
end

---@private
---@return NotebookView?
function M.current_view()
	local buf = vim.api.nvim_get_current_buf()
	local view = M.views[buf]
	if view then
		return view
	end
	for _, candidate in pairs(M.views) do
		if candidate.results_buf == buf then
			return candidate
		end
	end
	return nil
end

---@private
---@return NotebookController?
function M.current_controller()
	local view = M.current_view()
	return view and view.controller or nil
end

---@param opts? table User configuration
function M.setup(opts)
	config.setup(opts)

	if M._setup_done then
		return
	end
	M._setup_done = true

	vim.api.nvim_create_augroup("NotebookPlugin", { clear = true })

	vim.api.nvim_create_autocmd("BufReadCmd", {
		pattern = "*.ipynb",
		group = "NotebookPlugin",
		callback = function(ev)
			M.open(ev.file)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = "NotebookPlugin",
		callback = function(ev)
			local view = M.views[ev.buf]
			if view then
				M.views[ev.buf] = nil
				view:close()
			end
		end,
	})

	local cmds = {
		NotebookCellCreate = "create_cell",
		NotebookCellSplit = "split_cell",
		NotebookCellJoin = "join_cell",
		NotebookGoToError = "goto_error",
		NotebookGoToRunning = "goto_running",
		NotebookCellExecute = "execute_current_cell",
		NotebookExecuteAll = "execute_all",
		NotebookExecuteBelow = "execute_below",
		NotebookExecuteAbove = "execute_above",
		NotebookCellDelete = "delete_cell",
		NotebookCellCut = "cut_cell",
		NotebookCellCopy = "copy_cell",
		NotebookCellPaste = "paste_cell",
		NotebookCellSwitchType = "toggle_cell_type",
		NotebookCellToggleOutput = "toggle_cell_output",
		NotebookToggleOutputs = "toggle_outputs",
		NotebookCellMoveAbove = "move_cell_above",
		NotebookCellMoveBelow = "move_cell_below",
		NotebookSave = "save",
		NotebookKernelStart = "start_kernel",
		NotebookKernelRestart = "kernel_restart",
		NotebookKernelInterrupt = "kernel_interrupt",
		NotebookKernelKill = "kernel_shutdown",
	}

	for cmd, method in pairs(cmds) do
		vim.api.nvim_create_user_command(cmd, function()
			local controller = M.current_controller()
			if not controller then
				vim.notify("Not in a notebook", vim.log.levels.WARN)
				return
			end
			controller[method](controller)
		end, {})
	end

	vim.api.nvim_create_user_command("NotebookFocus", function(opts)
		local controller = M.current_controller()
		if not controller then
			vim.notify("Not in a notebook", vim.log.levels.WARN)
			return
		end
		controller:focus(opts.args)
	end, { nargs = "?" })
end

return M
