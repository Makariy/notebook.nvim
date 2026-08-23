-- Tests build stub websocket sessions and executers that only implement the few
-- methods the code under test calls, so the "missing required fields" check for
-- the full class shapes is not applicable here.
---@diagnostic disable:missing-fields

local Executer = require("notebook.execution.executer")
local NotebookSession = require("notebook.session.notebook_session")
local Notebook = require("notebook.notebook.notebook")
local Cell = require("notebook.notebook.cell")

---Feed a websocket-style message to an executer under a given msg_id.
---@param ex CommandExecuter
---@param msg_id string
---@param msg_type string
---@param content table
local function feed(ex, msg_id, msg_type, content)
	ex:handle_message(vim.json.encode({
		parent_header = { msg_id = msg_id },
		header = { msg_type = msg_type },
		content = content,
	}))
end

-- The executer dispatches every progress message type plus a terminal done event
-- once execute_reply + idle status arrive.
do
	local ex = Executer.new({ send = function() end })
	local got = {}
	local msg_id = ex:execute("print(1)", {
		on_progress = function(p)
			table.insert(got, p)
		end,
		on_done = function(status, count)
			table.insert(got, { done = status, count = count })
		end,
	})

	feed(ex, msg_id, "stream", { name = "stdout", text = "hi\n" })
	feed(ex, msg_id, "clear_output", { wait = true })
	feed(ex, msg_id, "display_data", { data = { ["text/plain"] = "x" } })
	feed(ex, msg_id, "error", { ename = "E", evalue = "boom", traceback = {} })
	feed(ex, msg_id, "execute_reply", { status = "ok", execution_count = 3 })
	feed(ex, msg_id, "status", { execution_state = "busy" })
	feed(ex, msg_id, "status", { execution_state = "idle" })

	check(got[1].type == "stream" and got[1].text == "hi\n", "EX1 stream forwarded")
	check(got[2].type == "clear" and got[2].wait == true, "EX2 clear_output forwarded with wait")
	check(got[3].type == "display_data", "EX3 display_data forwarded")
	check(got[4].type == "error" and got[4].ename == "E", "EX4 error forwarded")
	check(got[5].done == "ok" and got[5].count == 3, "EX5 done fires once after idle")
	check(#got == 5, "EX6 exactly five events, no duplicates")
end

-- A message for an unknown parent id is ignored.
do
	local ex = Executer.new({ send = function() end })
	local called = false
	ex:execute("x", {
		on_progress = function()
			called = true
		end,
	})
	feed(ex, "ghost", "stream", { name = "stdout", text = "x" })
	check(called == false, "EX7 unknown parent id is ignored")
end

-- The session holds stream output back while waiting for a clear, then emits it
-- once the wait clears (regression for the in_flight `waiting` shadowing bug).
do
	local nb = Notebook.new()
	local cell = Cell.code("print(1)")
	cell.metadata.id = "c1"
	table.insert(nb.cells, cell)
	local sess = NotebookSession.new(nb)

	local ex = Executer.new({ send = function() end })
	sess.command_executer = ex

	local captured
	local orig_execute = ex.execute
	ex.execute = function(self, code, dispatcher)
		captured = orig_execute(self, code, dispatcher)
		return captured
	end
	sess:execute_cell(1)

	local emitted = {}
	sess:subscribe({
		on_progress = function(_, out)
			table.insert(emitted, out.text)
		end,
	})

	feed(ex, captured, "clear_output", { wait = true })
	feed(ex, captured, "stream", { name = "stdout", text = "held\n" })
	feed(ex, captured, "clear_output", { wait = false })
	feed(ex, captured, "stream", { name = "stdout", text = "shown\n" })
	feed(ex, captured, "execute_reply", { status = "ok", execution_count = 1 })
	feed(ex, captured, "status", { execution_state = "idle" })

	check(#emitted == 1 and emitted[1] == "shown\n", "EX8 output suppressed while waiting, emitted after")
	check(#cell.outputs == 1 and cell.outputs[1].text == "shown\n", "EX9 held output is wiped by the follow-up clear")
	check(cell.execution_count == 1, "EX10 execution count applied on done")
end
