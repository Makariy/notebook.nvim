---@class WindowPair
---@field code_win integer
---@field results_win integer
local WindowPair = {}
WindowPair.__index = WindowPair

---@type WindowPair[]
local active_pairs = {}
local guard_installed = false

---@param winid integer
---@return boolean
local function is_managed_by_any(winid)
	for _, pair in ipairs(active_pairs) do
		if pair:is_managed(winid) then
			return true
		end
	end
	return false
end

---Install a single, plugin-wide guard (once, regardless of how many
---notebooks are open) that strips 'scrollbind' from any window that isn't
---part of a managed WindowPair.
---
---New windows - splits AND floats - inherit window-local options, including
---'scrollbind', from whichever window was current at creation time. So an
---LSP hover/signature float opened while a notebook window is focused would
---otherwise silently join the scrollbind group, and later get dragged into
---mirroring the notebook (or vice versa) the moment it's scrolled - which is
---exactly how "scrolling an LSP float scrolls the notebook" happened.
local function install_guard()
	if guard_installed then
		return
	end
	guard_installed = true
	vim.api.nvim_create_autocmd("WinNew", {
		callback = function()
			-- Deferred: the new window (and its buffer/options) may not be
			-- fully settled yet at the moment WinNew fires.
			vim.schedule(function()
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					local ok, has_scrollbind = pcall(function()
						return vim.wo[win].scrollbind
					end)
					local ok2, has_cursorbind = pcall(function()
						return vim.wo[win].cursorbind
					end)
					if not is_managed_by_any(win) then
						if ok and has_scrollbind then
							pcall(function() vim.wo[win].scrollbind = false end)
						end
						if ok2 and has_cursorbind then
							pcall(function() vim.wo[win].cursorbind = false end)
						end
					end
				end
			end)
		end,
	})
end

---@param code_win integer
---@param results_win integer
---@return WindowPair
function WindowPair.new(code_win, results_win)
	install_guard()
	local self = setmetatable({ code_win = code_win, results_win = results_win }, WindowPair)
	table.insert(active_pairs, self)
	return self
end

---Rebind to new window ids (e.g. after focus mode recreates a split).
---@param code_win integer
---@param results_win integer
function WindowPair:update(code_win, results_win)
	self.code_win = code_win
	self.results_win = results_win
end

---Stop tracking this pair (call when the notebook view closes).
function WindowPair:destroy()
	for i, pair in ipairs(active_pairs) do
		if pair == self then
			table.remove(active_pairs, i)
			break
		end
	end
end

---@param winid integer
---@return boolean
function WindowPair:is_managed(winid)
	return winid == self.code_win or winid == self.results_win
end

---@return integer[] Currently valid managed windows, code_win first.
function WindowPair:valid_wins()
	local out = {}
	if self.code_win and vim.api.nvim_win_is_valid(self.code_win) then
		table.insert(out, self.code_win)
	end
	if self.results_win and vim.api.nvim_win_is_valid(self.results_win) then
		table.insert(out, self.results_win)
	end
	return out
end

---The managed window currently focused by the user, or nil if focus is
---elsewhere (a float, another split, etc).
---@return integer?
function WindowPair:active()
	local cur = vim.api.nvim_get_current_win()
	if self:is_managed(cur) then
		return cur
	end
	return nil
end

---@param buf integer
---@return integer?
function WindowPair:window_for_buf(buf)
	for _, win in ipairs(self:valid_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			return win
		end
	end
	return nil
end

return WindowPair
