local M = {}

local DEFAULTS = {
	keymaps = {
		next_cell = "]c",
		previous_cell = "[c",
		focus = false,
	},
}

local config = vim.deepcopy(DEFAULTS)

---@param opts? table
function M.setup(opts)
	if not opts or next(opts) == nil then
		return
	end
	config = vim.tbl_deep_extend("force", config, opts)
end

---@return table effective configuration
function M.get()
	return vim.deepcopy(config)
end

return M
