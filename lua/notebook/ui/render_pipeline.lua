local codec = require("notebook.ui.codec")
local NotebookRenderer = require("notebook.ui.notebook_renderer")
local BufferPresenter = require("notebook.ui.buffer_presenter")
local ViewPorts = require("notebook.ui.view_ports")

local DEFAULT_WIDTH = 80

---@class RenderPipeline
local RenderPipeline = {}
RenderPipeline.__index = RenderPipeline

---@return RenderPipeline
function RenderPipeline.new()
	return setmetatable({}, RenderPipeline)
end

---@param view NotebookView
---@return boolean changed Whether either buffer was rewritten
function RenderPipeline:render(view)
	codec.ensure_ids(view.notebook)

	local ports = ViewPorts.from_view(view)
	local code_width = self:_win_width(ports.code_win, ports.results_win)
	local res_width = self:_win_width(ports.results_win, ports.code_win)

	local resolved
	if ports.results_win and vim.api.nvim_win_is_valid(ports.results_win) and view.image_renderer:available() then
		local img_width = math.max(1, res_width - 2)
		resolved = view.image_renderer:resolve(view.notebook, img_width)
	end

	local ut = vim.fn.undotree()
	local undo_locked = (ut.seq_cur ~= ut.seq_last)
	local undo_locked_heights = nil
	if undo_locked then
		local current_code = vim.api.nvim_buf_get_lines(ports.code_buf, 0, -1, false)
		undo_locked_heights = codec.physical_heights(current_code)
	end

	local layout = NotebookRenderer.build(
		view.notebook,
		code_width,
		res_width,
		resolved,
		view.execution_state,
		view.output_visibility:state(),
		undo_locked_heights
	)
	view._cell_starts = layout.cell_starts

	return BufferPresenter.apply(ports, layout, code_width, res_width, view.image_renderer, view.scroll_sync)
end

---@private
---@param win integer?
---@param fallback integer?
---@return integer
function RenderPipeline:_win_width(win, fallback)
	if win and vim.api.nvim_win_is_valid(win) then
		return vim.api.nvim_win_get_width(win)
	end
	if fallback and vim.api.nvim_win_is_valid(fallback) then
		return vim.api.nvim_win_get_width(fallback)
	end
	return DEFAULT_WIDTH
end

return RenderPipeline
