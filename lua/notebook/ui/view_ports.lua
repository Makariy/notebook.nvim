---
---@class ViewPorts
---@field code_buf integer
---@field results_buf integer
---@field code_win integer
---@field results_win integer
---@field cursor_win integer? Window whose cursor must survive a rewrite (the
---window the user is actually looking at, which may not be code_win)
---@field hl_ns integer

local M = {}

---@param view NotebookView
---@return ViewPorts
function M.from_view(view)
	return {
		code_buf = view.code_buf,
		results_buf = view.results_buf,
		code_win = view.code_win,
		results_win = view.results_win,
		cursor_win = view:cursor_win(),
		hl_ns = view.hl_ns,
	}
end

return M
