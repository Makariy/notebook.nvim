-- setup() must be safe to call more than once: plugin/notebook.lua auto-setups at
-- load, and a plugin manager (lazy.nvim) calls setup(opts) again. Configuration
-- merges on every call, but autocmds and user commands are registered only once.
local config = require("notebook.config")

local DEFAULT = { keymaps = { next_cell = "]c", previous_cell = "[c" } }
config.setup(DEFAULT)

-- First call from plugin/notebook.lua (defaults).
require("notebook").setup()

-- Second call, as lazy.nvim does with the user's opts: must not raise E174
-- (duplicate :command) and must merge the opts over the defaults.
local ok, err = pcall(function()
	require("notebook").setup({ keymaps = { next_cell = "]n" } })
end)
check(ok, "S1 second setup() does not error (idempotent)")
check(config.get().keymaps.next_cell == "]n", "S2 user opts merged")
check(config.get().keymaps.previous_cell == "[c", "S3 unspecified defaults kept")

-- A third call re-merges and stays safe.
local ok3, err3 = pcall(function()
	require("notebook").setup({ keymaps = { next_cell = false } })
end)
check(ok3, "S4 third setup() does not error")
check(config.get().keymaps.next_cell == false, "S5 latest opts win")

-- Commands exist exactly once.
local cmds = vim.api.nvim_get_commands({})
check(cmds["NotebookCellCreate"] ~= nil, "S6 cell command registered once")
check(cmds["NotebookKernelStart"] ~= nil, "S7 kernel command registered once")

config.setup(DEFAULT)
