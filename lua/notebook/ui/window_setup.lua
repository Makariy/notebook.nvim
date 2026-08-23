local WindowLayout = require("notebook.ui.window_layout")

local M = {}

---@param win integer
function M.configure_code_window(win)
	vim.wo[win].wrap = false
	vim.wo[win].scrollbind = true
	vim.wo[win].cursorbind = true
end

---@param win integer
function M.configure_results_window(win)
	vim.wo[win].wrap = false
	vim.wo[win].scrollbind = true
	vim.wo[win].cursorbind = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
end

---@param view NotebookView
function M.setup(view)
	view.code_buf = vim.api.nvim_get_current_buf()


	vim.bo[view.code_buf].buftype = ""
	vim.bo[view.code_buf].filetype = "python"
	vim.bo[view.code_buf].bufhidden = "hide"
	vim.bo[view.code_buf].swapfile = false

	view.results_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[view.results_buf].buftype = "nofile"
	vim.bo[view.results_buf].bufhidden = "hide"
	vim.bo[view.results_buf].swapfile = false
	vim.bo[view.results_buf].modifiable = false

	view.hl_ns = vim.api.nvim_create_namespace("notebook.ansi")

	vim.api.nvim_set_hl(0, "NotebookState", { fg = "#ffffff" })
	vim.api.nvim_set_hl(0, "NotebookSeparator", { fg = "#808080" })
	vim.api.nvim_set_hl(0, "NotebookMuted", { fg = "#9e9e9e" })

	-- 'scrollopt' governs how scrollbind windows align; "ver,jump" (Vim's
	-- default) matches absolute line numbers between windows, which is
	-- exactly correct here since the renderer always keeps the two buffers
	-- the same length with cell boundaries on identical line numbers.
	vim.o.scrollopt = "ver,jump"

	view.code_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(view.code_win, view.code_buf)
	M.configure_code_window(view.code_win)

	view.results_win = WindowLayout.split("rightbelow", view.results_buf, M.configure_results_window)
end

return M