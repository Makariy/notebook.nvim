local visual_guard = require("notebook.ui.visual_guard")

---@class ScrollSync
local ScrollSync = {}
ScrollSync.__index = ScrollSync

---@return ScrollSync
function ScrollSync.new()
	return setmetatable({ _pending = false }, ScrollSync)
end

---Force every 'scrollbind' window in the tab to match `win`'s current scroll
---position, via `:syncbind`.
---
---Skipped when the window that's actually current right now is a *different*
---window and it's in Visual/Select mode - switching to `win` would end that
---selection (leaving a window always ends Visual mode in it; this isn't
---specific to this plugin). When `win` is already the current window this
---check is moot: `nvim_win_call` on the already-current window never
---switches anything.
---@param win integer
function ScrollSync:sync_from(win)
	if self._pending then
		return
	end
	self._pending = true

	vim.schedule(function()
		self._pending = false
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		local current = vim.api.nvim_get_current_win()
		if current ~= win and visual_guard.active() then
			return
		end
		local target_w0 = vim.api.nvim_win_call(win, function()
			return vim.fn.line("w0")
		end)

		local out_of_sync = false
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if w ~= win and vim.wo[w].scrollbind then
				local w_w0 = vim.api.nvim_win_call(w, function()
					return vim.fn.line("w0")
				end)
				if w_w0 ~= target_w0 then
					out_of_sync = true
					break
				end
			end
		end

		if out_of_sync then
			pcall(vim.api.nvim_win_call, win, function()
				vim.cmd("silent! syncbind")
			end)
		end
	end)
end

return ScrollSync
