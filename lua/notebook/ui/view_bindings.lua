---@class ViewBindings
---@field view NotebookView
---@field autocmds integer[]
local ViewBindings = {}
ViewBindings.__index = ViewBindings

---@param view NotebookView
---@return ViewBindings
function ViewBindings.new(view)
	return setmetatable({ view = view, autocmds = {} }, ViewBindings)
end

function ViewBindings:setup()
	table.insert(
		self.autocmds,
		vim.api.nvim_create_autocmd("WinEnter", {
			buffer = self.view.results_buf,
			callback = function()
				if self.view.focus_mode:active() then
					return
				end
				if vim.api.nvim_win_is_valid(self.view.code_win) then
					local crow = vim.api.nvim_win_get_cursor(self.view.code_win)[1]
					pcall(vim.api.nvim_win_set_cursor, self.view.results_win, { crow, 0 })
				end
			end,
		})
	)

	local view = self.view

	local next_lhs = self.view.config.keymaps.next_cell
	if next_lhs then
		vim.keymap.set("n", next_lhs, function()
			view:goto_cell(view:get_current_cell_index() + vim.v.count1)
		end, { buffer = self.view.code_buf, desc = "Jump to next cell marker" })
	end
	local prev_lhs = self.view.config.keymaps.previous_cell
	if prev_lhs then
		vim.keymap.set("n", prev_lhs, function()
			view:goto_cell(view:get_current_cell_index() - vim.v.count1)
		end, { buffer = self.view.code_buf, desc = "Jump to previous cell marker" })
	end

	local focus_lhs = self.view.config.keymaps.focus
	if focus_lhs then
		vim.keymap.set("n", focus_lhs, function()
			self.view.focus_mode:toggle("code")
		end, { buffer = self.view.code_buf, desc = "Toggle wrapped code focus" })
	end

	table.insert(
		self.autocmds,
		vim.api.nvim_create_autocmd("WinResized", {
			callback = function(args)
				if tonumber(args.file) == self.view.results_win or tonumber(args.file) == self.view.code_win then
					self.view.scheduler:schedule()
				end
			end,
		})
	)

	table.insert(
		self.autocmds,
		vim.api.nvim_create_autocmd("FocusLost", {
			callback = function()
				self.view.image_renderer:hide_all()
			end,
		})
	)
	table.insert(
		self.autocmds,
		vim.api.nvim_create_autocmd("FocusGained", {
			callback = function()
				self.view.image_renderer:show_all()
			end,
		})
	)

	table.insert(
		self.autocmds,
		vim.api.nvim_create_autocmd("InsertEnter", {
			buffer = self.view.code_buf,
			callback = function()
				self.view.edit_mode:begin()
				self.view.image_renderer:begin_edit()
			end,
		})
	)
	table.insert(
		self.autocmds,
		vim.api.nvim_create_autocmd("InsertLeave", {
			buffer = self.view.code_buf,
			callback = function()
				self.view.edit_mode:finish()
				self.view.image_renderer:end_edit()
				self.view.scheduler:schedule()
				local win = self.view.window_pair:window_for_buf(self.view.code_buf)
				if win then
					self.view.scroll_sync:sync_from(win)
				end
			end,
		})
	)
end

function ViewBindings:teardown()
	for _, id in ipairs(self.autocmds) do
		pcall(vim.api.nvim_del_autocmd, id)
	end
	self.autocmds = {}
end

return ViewBindings
