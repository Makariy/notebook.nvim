local WindowSetup = require("notebook.ui.window_setup")
local WindowLayout = require("notebook.ui.window_layout")

---@class FocusMode
---@field view NotebookView
---@field mode string? "code", "output", or nil when the split is shown
local FocusMode = {}
FocusMode.__index = FocusMode

---@param view NotebookView
---@return FocusMode
function FocusMode.new(view)
	return setmetatable({ view = view, mode = nil }, FocusMode)
end

---@return boolean
function FocusMode:active()
	return self.mode ~= nil
end

---@param pane string?
function FocusMode:toggle(pane)
	---@type "code" | "output"
	local target = pane == "output" and "output" or "code"
	if self.mode == target then
		self:exit()
		return
	end
	if self.mode then
		self:exit()
	end
	self:enter(target)
end

---@private Show only the given pane, wrapped. Never errors on a stale window
---@param pane "code" | "output"
function FocusMode:enter(pane)
	local view = self.view
	local keep, hide = view.code_win, view.results_win
	if pane == "output" then
		keep, hide = view.results_win, view.code_win
	end

	if not (keep and vim.api.nvim_win_is_valid(keep)) then
		vim.notify("[notebook.nvim] Cannot focus the " .. pane .. " pane: its window is not open", vim.log.levels.WARN)
		return
	end
	if hide and vim.api.nvim_win_is_valid(hide) then
		vim.api.nvim_win_close(hide, false)
	end
	vim.wo[keep].wrap = true

	if pane == "code" then
		view.image_renderer:hide_all()
	end

	self.mode = pane
	view:render()
end

---@private Restore the side-by-side split
function FocusMode:exit()
	local view = self.view
	if self.mode == "output" then
		local results_win = view.results_win
		vim.api.nvim_win_call(results_win, function()
			view.code_win = WindowLayout.split("leftabove", view.code_buf, WindowSetup.configure_code_window)
		end)

		vim.wo[results_win].wrap = false
		view:_rebind_windows()
		vim.api.nvim_set_current_win(results_win)
		view.scroll_sync:sync_from(results_win)
	else
		local code_win = view.code_win
		vim.api.nvim_win_call(code_win, function()
			view.results_win = WindowLayout.split("rightbelow", view.results_buf, WindowSetup.configure_results_window)
		end)

		vim.wo[code_win].wrap = false
		view:_rebind_windows()
		vim.api.nvim_set_current_win(code_win)
		view.scroll_sync:sync_from(code_win)
	end

	self.mode = nil
	view:render()
end

return FocusMode
