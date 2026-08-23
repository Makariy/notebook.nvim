local InFlight = require("notebook.session.in_flight")

-- The supersede contract: begin() marks the authoritative msg, is_current()
-- filters stale callbacks, and the waiting flag gates output accumulation.
do
	local f = InFlight.new()

	check(f:is_current("c1", "m1") == false, "IF1 no execution is current before begin")

	f:begin("c1", "m1")
	check(f:is_current("c1", "m1") == true, "IF2 current msg id is authoritative")
	check(f:is_current("c1", "m2") == false, "IF3 a stale msg id is not current")

	-- Re-execution supersedes: the new msg id wins.
	f:begin("c1", "m2")
	check(f:is_current("c1", "m1") == false, "IF4 superseded msg id is stale")
	check(f:is_current("c1", "m2") == true, "IF5 re-execution becomes current")

	check(f:is_waiting("c1") == false, "IF6 not waiting by default")
	f:set_waiting("c1", true)
	check(f:is_waiting("c1") == true, "IF7 waiting flag set")
	f:set_waiting("c1", false)
	check(f:is_waiting("c1") == false, "IF8 waiting flag cleared")

	f:finish("c1")
	check(f:is_current("c1", "m2") == false, "IF9 finish clears the execution")
	check(f:is_waiting("c1") == false, "IF9 finish clears the waiting flag")
end
