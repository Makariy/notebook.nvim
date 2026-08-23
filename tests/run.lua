-- Minimal headless test runner. Usage:
--   nvim --headless -u NONE -n -c "luafile tests/run.lua"
vim.opt.rtp:prepend(".")

-- Each opened view creates a vertical split; give the grid enough columns that
-- the whole suite can run without exhausting the window width (E36).
vim.opt.columns = 200
vim.opt.lines = 40

local tests = vim.fn.glob("tests/unit/*.lua", false, true)
table.sort(tests)

local total = 0
local failed = 0
local current = ""

---@param cond boolean
---@param msg string
_G.check = function(cond, msg)
	total = total + 1
	if cond then
		print(string.format("  [PASS] %s", msg))
	else
		failed = failed + 1
		print(string.format("  [FAIL] %s: %s", current, msg))
	end
end

for _, file in ipairs(tests) do
	current = file
	print("== " .. file)
	local ok, err = pcall(dofile, file)
	if not ok then
		failed = failed + 1
		print("  [ERROR] " .. tostring(err))
	end
end

print(string.format("\n%d checks, %d failure(s)", total, failed))

if failed > 0 then
	os.exit(1)
end
os.exit(0)
