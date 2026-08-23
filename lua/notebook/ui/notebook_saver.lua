local IpynbRenderer = require("notebook.notebook.ipynb_renderer")

local M = {}

---@param path string
---@param notebook Notebook
---@return boolean ok Whether the file was written
function M.save(path, notebook)
	local dir = vim.fn.fnamemodify(path, ":h")
	local tmp = dir .. "/." .. vim.fn.fnamemodify(path, ":t") .. ".tmp" .. vim.fn.getpid()

	local f, open_err = io.open(tmp, "w")
	if not f then
		vim.notify("Failed to save " .. path .. ": " .. tostring(open_err), vim.log.levels.ERROR)
		return false
	end

	local written, write_err = f:write(IpynbRenderer.render(notebook))
	f:close()
	if not written then
		os.remove(tmp)
		vim.notify("Failed to save " .. path .. ": " .. tostring(write_err), vim.log.levels.ERROR)
		return false
	end

	local renamed, rename_err = os.rename(tmp, path)
	if not renamed then
		os.remove(tmp)
		vim.notify("Failed to save " .. path .. ": " .. tostring(rename_err), vim.log.levels.ERROR)
		return false
	end

	vim.notify("Notebook saved to " .. path, vim.log.levels.INFO)
	return true
end

return M
