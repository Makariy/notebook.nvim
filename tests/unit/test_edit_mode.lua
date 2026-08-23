local EditMode = require("notebook.ui.edit_mode")

-- A fresh EditMode reports inactive.
do
	local m = EditMode.new()
	check(m:active() == false, "E1 fresh edit mode is inactive")
end

-- begin()/finish() toggle the flag that keeps renders out of typing.
do
	local m = EditMode.new()
	m:begin()
	check(m:active() == true, "E2 active while in an insert session")
	m:finish()
	check(m:active() == false, "E3 inactive after leaving insert")
end
