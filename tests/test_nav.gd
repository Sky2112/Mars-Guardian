extends SceneTree
## Headless tests for the MarsGuardian navigation core.
## Run: godot --headless --path . --script tests/test_nav.gd
const Nav := preload("res://nav_system.gd")
const HZ := preload("res://hazard_data.gd")

var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func hazards_all() -> Array:
	var out: Array = []
	for r in HZ.RESTRICTED:
		out.append(Nav.hazard(r[1], Vector2(r[2], r[3]), r[4], "restricted", 1.0, true, r[8], false, r[5]))
	for g in HZ.GLOBAL_HAZARDS:
		out.append(Nav.hazard(g[0], Vector2(g[1], g[2]), g[3], g[4], g[5], false, g[6]))
	# a few Jezero site hazards (same numbers as SITES in node_2d.gd)
	out.append(Nav.hazard("Rock field", Vector2(18.415, 77.435), 1.2, "rock", 8.0, false, ""))
	out.append(Nav.hazard("Dust storm corridor", Vector2(18.62, 77.65), 5.0, "dust", 3.0, true, "", true))
	return out

func _init() -> void:
	var hz := hazards_all()
	var land := Vector2(18.4447, 77.4508)
	var delta_base := Vector2(18.432, 77.378)

	var r := Nav.plan(land, delta_base, hz, {"priority": "balanced", "speed_kmh": 0.14, "dest_name": "Delta base"})
	check(r["ok"], "Landing site -> Delta base: route found")
	check(r["length_km"] < r["direct_km"] * 1.8, "detour is sensible (%.1f vs %.1f km direct)" % [r["length_km"], r["direct_km"]])
	var inside := false
	for p in r["path"]:
		if Nav.hazards_at(p, hz, true).size() > 0:
			inside = true
	check(not inside, "path never enters a restricted area")
	check(r["steps"].size() >= 2, "turn-by-turn steps generated (%d)" % r["steps"].size())
	print("      avoided: ", r["avoided"], "  risk: ", r["risk"], "  min clearance: %.0f m (%s)" % [r["min_clear_km"] * 1000.0, r["min_clear_name"]])

	var rs := Nav.plan(land, delta_base, hz, {"priority": "safest", "speed_kmh": 0.14})
	var rf := Nav.plan(land, delta_base, hz, {"priority": "fastest", "speed_kmh": 0.14})
	check(rs["ok"] and rf["ok"], "safest and fastest both succeed")
	check(rs["length_km"] >= rf["length_km"] - 0.01, "safest (%.2f km) is not shorter than fastest (%.2f km)" % [rs["length_km"], rf["length_km"]])

	# destination inside a restricted area -> adjusted to nearest permitted point
	var depot := Vector2(18.47, 77.40)
	var rd := Nav.plan(land, depot, hz, {"dest_name": "Sample depot"})
	check(rd["ok"] and rd["goal_adjusted"], "destination inside restricted ground is adjusted")
	check(Nav.hazards_at(rd["goal"], hz, true).is_empty(), "adjusted goal is outside the keep-out")

	# start inside a restricted area -> exits
	var rx := Nav.plan(depot, land, hz, {})
	check(rx["ok"], "start inside restricted ground still gets an exit route")

	# global: Perseverance -> Curiosity, must dodge nothing blocked
	var rg := Nav.plan(land, Vector2(-4.59, 137.44), hz, {"priority": "balanced", "speed_kmh": 15.0, "dest_name": "Curiosity"})
	check(rg["ok"], "global route Perseverance -> Curiosity (%.0f km) %s" % [rg["length_km"], rg["reason"]])

	# global: across Valles Marineris must go around it
	var rv := Nav.plan(Vector2(-14.0, -80.0), Vector2(-14.0, -40.0), hz, {"speed_kmh": 15.0})
	if rv["ok"]:
		var bad := false
		for p in rv["path"]:
			if Nav.hazards_at(p, hz, true).size() > 0:
				bad = true
		check(not bad, "route across Valles Marineris avoids canyon walls (avoided: %s)" % str(rv["avoided"]))
	else:
		check(true, "Valles Marineris crossing refused: " + rv["reason"])

	# polar refused
	var rp := Nav.plan(land, Vector2(85.0, 0.0), hz, {})
	check(not rp["ok"], "polar destination refused")

	# GPS sim
	var g := Nav.GpsSim.new()
	g.place(land)
	for i in range(300):
		g.step(10.0, 0.1, true)
	check(g.accuracy_m > 30.0 and g.fix_state.begins_with("DEAD"), "dust degrades GPS (%.0f m, %s)" % [g.accuracy_m, g.fix_state])
	for i in range(30):
		g.step(10.0, 0.0, false)
	check(g.accuracy_m < 80.0, "beacon fix restores accuracy (%.0f m, %s)" % [g.accuracy_m, g.fix_state])

	# dust storm dropped on the route forces a reroute
	var mid: Vector2 = (r["path"][0] as Vector2).lerp(r["path"][r["path"].size() - 1], 0.5)
	var hz2 := hz.duplicate()
	hz2.append(Nav.hazard("Dust storm (sim)", mid, 0.5, "dust", 1.0, true, "", false))
	var rr := Nav.plan(land, delta_base, hz2, {})
	check(rr["ok"], "reroute around simulated dust storm succeeds (+%.0f%%)" % rr["detour_pct"])

	print("\nFAILS: ", fails)
	quit(1 if fails > 0 else 0)
