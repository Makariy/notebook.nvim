local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local helpers = require("tests.helpers")

-- The kernel lifecycle user commands must reach KernelActions through the
-- controller delegates (init.lua dispatches `controller[method]()`, so removing
-- these methods would crash :NotebookKernelStart/Restart/Interrupt/Kill).
do
	local nb = Notebook.new()
	local c = Cell.code("print(1)")
	c.metadata.id = "c1"
	table.insert(nb.cells, c)
	local view = helpers.open_view(nb, "test_commands.ipynb")
	vim.wait(30)

	local called = {}
	view.controller.kernel = {
		start = function()
			called[#called + 1] = "start"
		end,
		restart = function()
			called[#called + 1] = "restart"
		end,
		interrupt = function()
			called[#called + 1] = "interrupt"
		end,
		shutdown = function()
			called[#called + 1] = "shutdown"
		end,
	}

	view.controller:start_kernel()
	view.controller:kernel_restart()
	view.controller:kernel_interrupt()
	view.controller:kernel_shutdown()

	check(#called == 4, "CM1 all four kernel commands dispatch")
	check(called[1] == "start" and called[2] == "restart", "CM2 start/restart reach KernelActions")
	check(called[3] == "interrupt" and called[4] == "shutdown", "CM3 interrupt/shutdown reach KernelActions")

	-- The :Notebook* commands are all registered by setup().
	require("notebook").setup()
	local commands = vim.api.nvim_get_commands({})
	for _, cmd in ipairs({
		"NotebookKernelStart",
		"NotebookKernelRestart",
		"NotebookKernelInterrupt",
		"NotebookKernelKill",
	}) do
		check(commands[cmd] ~= nil, "CM4 " .. cmd .. " is registered")
	end
end
