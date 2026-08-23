---
local codec = require("notebook.ui.codec")
local reconcile = require("notebook.notebook.reconcile")
local Undo = require("notebook.ui.undo")
local ExecutionState = require("notebook.notebook.execution_state")
local NotebookSession = require("notebook.session.notebook_session")
local NotebookController = require("notebook.ui.notebook_controller")
local WindowPair = require("notebook.ui.window_pair")
local ScrollSync = require("notebook.ui.scroll_sync")
local ImageRenderer = require("notebook.ui.image_renderer")
local RenderScheduler = require("notebook.ui.render_scheduler")
local RenderPipeline = require("notebook.ui.render_pipeline")
local EditMode = require("notebook.ui.edit_mode")
local WindowSetup = require("notebook.ui.window_setup")
local WindowLayout = require("notebook.ui.window_layout")
local ViewBindings = require("notebook.ui.view_bindings")
local CellNavigation = require("notebook.ui.cell_navigation")
local FocusMode = require("notebook.ui.focus_mode")
local OutputVisibility = require("notebook.ui.output_visibility")
local config = require("notebook.config")

---@class INotebookView 
---@field notebook Notebook
---@field path string
---@field execution_state ExecutionState
---@field focus_mode FocusMode
---@field sync fun(self: INotebookView)
---@field render fun(self: INotebookView)
---@field get_current_cell_index fun(self: INotebookView): integer
---@field get_cell_start fun(self: INotebookView, index: integer): integer?
---@field get_cursor fun(self: INotebookView): integer[]
---@field set_cursor fun(self: INotebookView, row: integer, col: integer)
---@field goto_cell fun(self: INotebookView, index: integer)
---@field line_count fun(self: INotebookView): integer
---@field mark_saved fun(self: INotebookView)
---@field toggle_cell_output fun(self: INotebookView, cell_id: string)
---@field toggle_all_outputs fun(self: INotebookView)
---@field retire_cell fun(self: INotebookView, cell: Cell)
---@field current_pane fun(self: INotebookView): "code" | "output"

---@class NotebookView : INotebookView
---@field notebook Notebook
---@field path string
---@field graveyard table<string, Cell>
---@field session NotebookSession
---@field controller NotebookController
---@field scheduler RenderScheduler
---@field bindings ViewBindings
---@field edit_mode EditMode
---@field focus_mode FocusMode
---@field execution_state ExecutionState
---@field image_renderer ImageRenderer
---@field pipeline RenderPipeline
---@field config table
---@field output_visibility OutputVisibility
---@field code_buf integer
---@field results_buf integer
---@field code_win integer
---@field results_win integer
---@field hl_ns integer
---@field _cell_starts integer[] 0-based marker row per cell, from the last render
local NotebookView = {}
NotebookView.__index = NotebookView

---@param notebook Notebook
---@param path string?
---@return NotebookView
function NotebookView.new(notebook, path)
	local self = setmetatable({}, NotebookView)
	self.notebook = notebook
	self.path = path or "notebook.ipynb"
	self.graveyard = {}
	self.execution_state = ExecutionState.new()
	self.session = NotebookSession.new(self.notebook)
	self.controller = NotebookController.new(self, self.session)
	self.image_renderer = ImageRenderer.new(self)
	self.config = config.get()
	self.output_visibility = OutputVisibility.new()
	self.edit_mode = EditMode.new()
	self.focus_mode = FocusMode.new(self)
	self.bindings = ViewBindings.new(self)
	self.scheduler = RenderScheduler.new(function()
		self:sync()
	end, function()
		return self:_editing()
	end)
	self.pipeline = RenderPipeline.new()

	self.session:subscribe({
		on_progress = function()
			self.scheduler:schedule()
		end,
		on_changed = function()
			self.scheduler:schedule()
		end,
		on_done = function(cell_id, status)
			self.execution_state:set_done(cell_id, status == "ok")
			if self.code_buf and vim.api.nvim_buf_is_valid(self.code_buf) then
				self.scheduler:schedule()
			end
		end,
	})

	return self
end

function NotebookView:_setup_lifecycle()
	self._lifecycle_group = vim.api.nvim_create_augroup("NotebookLifecycle_" .. self.code_buf, { clear = true })

	local function check_layout(ev)
		

		vim.schedule(function()
			if self.focus_mode:active() then return end
			if not vim.api.nvim_buf_is_valid(self.code_buf) or not vim.api.nvim_buf_is_valid(self.results_buf) then
				return
			end

			local code_w = nil
			local res_w = nil

			for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.api.nvim_win_is_valid(w) then
					local b = vim.api.nvim_win_get_buf(w)
					if b == self.code_buf then
						code_w = w
					elseif b == self.results_buf then
						res_w = w
					end
				end
			end

			local function safe_close(w)
				if #vim.api.nvim_list_wins() == 1 then
					pcall(vim.cmd, "q")
				else
					pcall(vim.api.nvim_win_close, w, false)
				end
			end

			if ev.event == "BufWinEnter" then
				if ev.buf == self.code_buf and code_w and not res_w then
					vim.api.nvim_win_call(code_w, function()
						self.code_win = code_w
						WindowSetup.configure_code_window(self.code_win)
						self.results_win = WindowLayout.split("rightbelow", self.results_buf, WindowSetup.configure_results_window)
					end)
					self:_rebind_windows()
					self.scroll_sync:sync_from(self.code_win)
				elseif ev.buf == self.results_buf and res_w and not code_w then
					vim.api.nvim_win_call(res_w, function()
						self.results_win = res_w
						WindowSetup.configure_results_window(self.results_win)
						self.code_win = WindowLayout.split("leftabove", self.code_buf, WindowSetup.configure_code_window)
					end)
					self:_rebind_windows()
					self.scroll_sync:sync_from(self.code_win)
				end
			elseif ev.event == "BufWinLeave" then
				if ev.buf == self.code_buf and not code_w and res_w then
					safe_close(res_w)
				elseif ev.buf == self.results_buf and not res_w and code_w then
					safe_close(code_w)
				end
			end
		end)
	end

	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		group = self._lifecycle_group,
		buffer = self.code_buf,
		callback = check_layout,
	})
	vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave" }, {
		group = self._lifecycle_group,
		buffer = self.results_buf,
		callback = check_layout,
	})
end

function NotebookView:open()
	codec.ensure_ids(self.notebook)

	WindowSetup.setup(self)
	self:_rebind_windows()
	self:_setup_lifecycle()

	self:render()
	self.bindings:setup()

	vim.api.nvim_set_current_win(self.code_win)
	vim.api.nvim_win_set_cursor(self.code_win, { 1, 0 })
	vim.bo[self.code_buf].modified = false
	Undo.clear(self.code_buf)

	self.scheduler:attach(self.code_buf)
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = self._lifecycle_group,
		buffer = self.code_buf,
		callback = function()
			-- No-op to intercept native :w and prevent autosave performance killer
		end,
	})

	vim.api.nvim_create_autocmd("QuitPre", {
		group = self._lifecycle_group,
		buffer = self.code_buf,
		callback = function()
			if vim.bo[self.code_buf].modified then
				local choice = vim.fn.confirm("Notebook changes will be lost if you don't save, would you like to save it?", "&Yes\n&No\n&Cancel", 1)
				if choice == 1 then
					self.controller:save()
					vim.bo[self.code_buf].modified = false
				elseif choice == 2 then
					vim.bo[self.code_buf].modified = false
				end
			end
		end,
	})


end

function NotebookView:close()

	if self._lifecycle_group then
		pcall(vim.api.nvim_del_augroup_by_id, self._lifecycle_group)
	end
	if self.window_pair then
		self.window_pair:destroy()
	end
	if self.image_renderer then
		self.image_renderer:clear_all()
	end
	if self.session then
		self.session:shutdown()
	end
	self.bindings:teardown()
	if self.results_buf and vim.api.nvim_buf_is_valid(self.results_buf) then
		pcall(vim.api.nvim_buf_delete, self.results_buf, { force = true })
	end
end

---@private Rebind WindowPair to the current code_win/results_win. Called
---once from open(), and again whenever focus mode recreates a split.
function NotebookView:_rebind_windows()
	if not self.window_pair then
		self.window_pair = WindowPair.new(self.code_win, self.results_win)
	else
		self.window_pair:update(self.code_win, self.results_win)
	end

	if not self.scroll_sync then
		self.scroll_sync = ScrollSync.new()
	end
end

---@return boolean
function NotebookView:_editing()
	return self.edit_mode:active()
end

function NotebookView:sync()
	local lines = vim.api.nvim_buf_get_lines(self.code_buf, 0, -1, false)
	local specs = codec.parse_lines(lines)
	reconcile.reconcile(self.notebook, specs, self.graveyard)
	self:render()
end

function NotebookView:mark_saved()
	vim.bo[self.code_buf].modified = false
end

---Preserve a removed cell object (and its outputs) so a later reconcile by id
---can resurrect it instead of treating it as new.
---@param cell Cell
function NotebookView:retire_cell(cell)
	if cell and cell.metadata and cell.metadata.id then
		self.graveyard[cell.metadata.id] = cell
	end
end

---@param cell_id string
function NotebookView:toggle_cell_output(cell_id)
	self.output_visibility:toggle(cell_id)
end

function NotebookView:toggle_all_outputs()
	self.output_visibility:toggle_all(self.notebook)
end

---@return "code" | "output" The pane the current window is showing
function NotebookView:current_pane()
	local cur = vim.api.nvim_get_current_win()
	if cur and vim.api.nvim_win_is_valid(cur) and vim.api.nvim_win_get_buf(cur) == self.results_buf then
		return "output"
	end
	return "code"
end

function NotebookView:render()
	codec.ensure_ids(self.notebook)
	if self.scheduler.in_render then
		return
	end
	if self:_editing() then
		return
	end
	self.scheduler:begin_render()
	local ok, result = xpcall(function()
		return self.pipeline:render(self)
	end, debug.traceback)
	self.scheduler:end_render()
	if not ok then
		vim.notify("[notebook.nvim] Render failed: " .. tostring(result), vim.log.levels.ERROR)
		return
	end
	if result then
		self:_schedule_syncbind()
	end
end

---@private Re-align the two windows' scroll positions after the buffers changed.
function NotebookView:_schedule_syncbind()
	if self:_editing() then
		return
	end
	vim.schedule(function()
			if self.focus_mode:active() then return end
		if vim.api.nvim_win_is_valid(self.code_win) and vim.api.nvim_win_is_valid(self.results_win) then
			vim.api.nvim_win_call(self.code_win, function()
				vim.cmd("syncbind")
			end)
		end
	end)
end

---@private The window the cursor-based navigation should act on
---@return integer?
function NotebookView:_nav_win()
	if self.code_win and vim.api.nvim_win_is_valid(self.code_win) then
		return self.code_win
	end
	if self.results_win and vim.api.nvim_win_is_valid(self.results_win) then
		return self.results_win
	end
	return nil
end

---The window whose cursor the user is actually looking at. When the
---current window shows the code buffer (e.g. a floating window opened by
---another plugin such as zen-mode), that window is the source of truth for
---cell navigation; otherwise fall back to the notebook's own code/results
---window. Without this, a float over the code buffer edits in one window while
---execution reads the stale cursor of the hidden code window.
---@return integer?
function NotebookView:cursor_win()
	local cur = vim.api.nvim_get_current_win()
	if cur and vim.api.nvim_win_is_valid(cur) and vim.api.nvim_win_get_buf(cur) == self.code_buf then
		return cur
	end
	return self:_nav_win()
end

---@return integer 1-based index of the cell under the cursor
function NotebookView:get_current_cell_index()
	local win = self:cursor_win()
	if not win then
		return 1
	end
	return CellNavigation.current_index(win, self._cell_starts)
end

---@param index integer
---@return integer? 0-based marker row of the cell, or nil
function NotebookView:get_cell_start(index)
	return CellNavigation.cell_start(self._cell_starts, index)
end

---@param index integer
function NotebookView:goto_cell(index)
	local win = self:cursor_win()
	if win then
		CellNavigation.goto_cell(win, self._cell_starts, index)
		self.scroll_sync:sync_from(win)
	end
end

---@return integer[] { row, col } (1-based)
function NotebookView:get_cursor()
	local win = self:cursor_win()
	if not win then
		return { 1, 0 }
	end
	local cursor = vim.api.nvim_win_get_cursor(win)
	return { cursor[1], cursor[2] }
end

---@param row integer
---@param col integer
function NotebookView:set_cursor(row, col)
	local win = self:cursor_win()
	if win then
		vim.api.nvim_win_set_cursor(win, { row, col })
		self.scroll_sync:sync_from(win)
	end
end

---@return integer
function NotebookView:line_count()
	return vim.api.nvim_buf_line_count(self.code_buf)
end

return NotebookView
