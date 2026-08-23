local codec = require("notebook.ui.codec")

local M = {}

---@private Cheap line-array equality (faster than vim.deep_equal for this).
---@param a string[]
---@param b string[]
---@return boolean
local function same_lines(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

---@private Whether a rewrite only changes decoration (markers/ids/padding), not
---user content. Such a rewrite joins the previous undo block instead of
---recording its own undo step, so `u` reverts real user text.
---@param current string[]
---@param target string[]
---@return boolean
local function content_equivalent(current, target)
	local cur_blocks = codec.cell_blocks(current)
	local tgt_blocks = codec.cell_blocks(target)
	local cur_specs = codec.parse_lines(current)
	local tgt_specs = codec.parse_lines(target)
	if #cur_blocks ~= #tgt_blocks or #cur_specs ~= #tgt_specs then
		return false
	end
	for i, a in ipairs(cur_blocks) do
		local b = tgt_blocks[i]
		if a.type ~= b.type then
			return false
		end
		if a.id ~= b.id and not (a.id == nil and b.id ~= nil) then
			return false
		end
	end
	for i, a in ipairs(cur_specs) do
		if a.cell_type ~= tgt_specs[i].cell_type or a.source ~= tgt_specs[i].source then
			return false
		end
	end
	return true
end

---@param a string[]
---@param b string[]
---@return boolean
function M.same_lines(a, b)
	return same_lines(a, b)
end

---@param buf integer
---@param current string[]
---@param target string[]
---@return boolean changed
function M.write(buf, current, target)
	if same_lines(current, target) then
		return false
	end

	vim.api.nvim_buf_call(buf, function()
		if content_equivalent(current, target) then
			local ut = vim.fn.undotree()
			if ut.seq_cur ~= ut.seq_last then
				return false
			end
			pcall(vim.cmd, "undojoin")
		end

		local cur_str = table.concat(current, "\n") .. "\n"
		local tgt_str = table.concat(target, "\n") .. "\n"
		local diff = vim.text.diff(cur_str, tgt_str, { result_type = "indices" })

		if not diff then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, target)
			return
		end

		-- Apply hunks in reverse order so line indices remain stable during patching
		for i = #diff, 1, -1 do
			local d = diff[i]
			local start_a, count_a, start_b, count_b = d[1], d[2], d[3], d[4]

			local replacement = {}
			for j = start_b, start_b + count_b - 1 do
				table.insert(replacement, target[j])
			end

			local row_start, row_end
			if count_a == 0 then
				row_start = start_a
				row_end = start_a
			else
				row_start = start_a - 1
				row_end = start_a - 1 + count_a
			end

			vim.api.nvim_buf_set_lines(buf, row_start, row_end, false, replacement)
		end
	end)
	return true
end

return M
