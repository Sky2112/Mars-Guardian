extends RefCounted
## MarsGuardian navigation core: hazard-aware route planner, turn-by-turn guidance
## and a simulated positioning (GPS-like) receiver. Pure logic, no UI, so it can be
## unit-tested headless (see tests/test_nav.gd).
##
## Mars has no GPS satellites. Real rovers use visual odometry and orbiter/beacon fixes,
## so the simulator models exactly that: drift while driving, correction at beacon fixes,
## and degraded accuracy inside dust.
##
## Coordinates: Vector2(lat, lon) in degrees, east-positive. Local maths in km (x east, y north).

const KM_DEG := 59.27
const MARS_R_KM := 3389.5
const DEG := PI / 180.0
const MAX_LAT := 78.0

# ------------------------------------------------------------------ geometry
static func wrap_dlon(d: float) -> float:
	return fposmod(d + 180.0, 360.0) - 180.0

static func to_xy(ll: Vector2, ref: Vector2) -> Vector2:
	return Vector2(wrap_dlon(ll.y - ref.y) * KM_DEG * cos(ref.x * DEG), (ll.x - ref.x) * KM_DEG)

static func from_xy(p: Vector2, ref: Vector2) -> Vector2:
	var c := maxf(cos(ref.x * DEG), 0.05)
	return Vector2(ref.x + p.y / KM_DEG, fposmod(ref.y + p.x / (KM_DEG * c) + 180.0, 360.0) - 180.0)

static func dist_km(a: Vector2, b: Vector2) -> float:
	var la1 := a.x * DEG
	var la2 := b.x * DEG
	var dla := la2 - la1
	var dlo := (b.y - a.y) * DEG
	var h := sin(dla * 0.5) * sin(dla * 0.5) + cos(la1) * cos(la2) * sin(dlo * 0.5) * sin(dlo * 0.5)
	return 2.0 * MARS_R_KM * asin(minf(1.0, sqrt(h)))

static func bearing(a: Vector2, b: Vector2) -> float:
	var p1 := a.x * DEG
	var p2 := b.x * DEG
	var dl := (b.y - a.y) * DEG
	var y := sin(dl) * cos(p2)
	var x := cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	return fposmod(atan2(y, x) / DEG, 360.0)

static func compass(deg: float) -> String:
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[int(round(fposmod(deg, 360.0) / 45.0)) % 8]

static func fmt_dist(km: float) -> String:
	if km < 1.0:
		return "%d m" % int(round(km * 1000.0 / 10.0) * 10.0)
	if km < 100.0:
		return "%.1f km" % km
	return "%d km" % int(round(km))

static func fmt_dur(hours: float) -> String:
	if hours < 1.0:
		return "%d min" % int(round(hours * 60.0))
	if hours < 48.0:
		return "%.1f h" % hours
	return "%d sols" % int(round(hours / 24.6597))

# ------------------------------------------------------------------ hazards
## Hazard dictionary. blocked = hard keep-out. relax = may be crossed as a last resort.
static func hazard(h_name: String, ll: Vector2, r_km: float, kind: String, penalty: float,
		blocked: bool, why: String, relax: bool = false, r_in_km: float = 0.0) -> Dictionary:
	return {"name": h_name, "ll": ll, "r": r_km, "r_in": r_in_km, "kind": kind, "pen": penalty,
		"blocked": blocked, "relax": relax, "why": why}

static func hazard_contains(h: Dictionary, ll: Vector2, extra_km: float = 0.0) -> bool:
	var d := dist_km(ll, h["ll"])
	return d <= float(h["r"]) + extra_km and d >= float(h["r_in"]) - extra_km

## Signed distance to a hazard's edge in km (negative = inside).
static func edge_dist(h: Dictionary, ll: Vector2) -> float:
	var d := dist_km(ll, h["ll"])
	var r_in: float = h["r_in"]
	if r_in > 0.0:
		return minf(d - float(h["r"]), r_in - d) if d < float(h["r"]) else d - float(h["r"])
	return d - float(h["r"])

static func hazards_at(ll: Vector2, hazards: Array, only_blocked: bool = false) -> Array:
	var out: Array = []
	for h in hazards:
		if only_blocked and not bool(h["blocked"]):
			continue
		if hazard_contains(h, ll):
			out.append(h)
	return out

# ------------------------------------------------------------------ planner
## opts: priority "safest"|"balanced"|"fastest", air bool, speed_kmh float, dest_name String
static func plan(start: Vector2, goal: Vector2, hazards: Array, opts: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "reason": "", "path": [], "warnings": [], "steps": [], "length_km": 0.0,
		"direct_km": dist_km(start, goal), "detour_pct": 0.0, "avoided": [], "exposure": [],
		"min_clear_km": INF, "min_clear_name": "", "risk": "UNKNOWN", "goal_adjusted": false,
		"goal": goal, "relaxed": false, "time_h": 0.0}
	if absf(start.x) > MAX_LAT or absf(goal.x) > MAX_LAT:
		res["reason"] = "Polar ground routing is not available above %d° latitude (CO2 frost, ice cliffs, no sunlight in winter)." % int(MAX_LAT)
		return res
	if res["direct_km"] < 0.02:
		res["reason"] = "You are already at the destination."
		return res
	var sol := _solve(start, goal, hazards, opts, false)
	if sol.is_empty():
		sol = _solve(start, goal, hazards, opts, true)
		if not sol.is_empty():
			res["relaxed"] = true
			res["warnings"].append("No route avoids active NO-GO weather. This path crosses it. HOLD position until the area clears.")
	if sol.is_empty():
		res["reason"] = "No safe route exists. Restricted areas and cliffs block every path to the destination."
		return res
	var path: Array = sol["path"]
	res["ok"] = true
	res["path"] = path
	res["goal"] = path[path.size() - 1]
	res["goal_adjusted"] = bool(sol["goal_adjusted"])
	for w in sol["warnings"]:
		res["warnings"].append(w)
	var len_km := 0.0
	for i in range(path.size() - 1):
		len_km += dist_km(path[i], path[i + 1])
	res["length_km"] = len_km
	var direct := dist_km(start, res["goal"])
	res["direct_km"] = direct
	res["detour_pct"] = maxf(0.0, (len_km / maxf(direct, 0.001) - 1.0) * 100.0)
	var spd := float(opts.get("speed_kmh", 0.14))
	res["time_h"] = len_km / maxf(spd, 0.001)
	res["avoided"] = _avoided(start, res["goal"], hazards)
	_analyze(res, hazards)
	res["steps"] = build_steps(path, hazards, str(opts.get("dest_name", "destination")))
	return res

static func _solve(start: Vector2, goal: Vector2, hazards: Array, o: Dictionary, relax: bool) -> Dictionary:
	var priority: String = o.get("priority", "balanced")
	var air: bool = o.get("air", false)
	var pen_scale := 1.0
	var buf := 0.15
	var halo_w := 0.5
	if priority == "safest":
		pen_scale = 2.0
		buf = 0.30
		halo_w = 1.5
	elif priority == "fastest":
		pen_scale = 0.5
		buf = 0.05
		halo_w = 0.0
	var ref := Vector2((start.x + goal.x) * 0.5, start.y + wrap_dlon(goal.y - start.y) * 0.5)
	var a := to_xy(start, ref)
	var b := to_xy(goal, ref)
	var ext := a.distance_to(b)
	var margin := maxf(2.0, ext * 0.4)
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(margin, margin)
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(margin, margin)
	var cell := clampf(maxf(mx.x - mn.x, mx.y - mn.y) / 170.0, 0.04, 40.0)
	var cols := int(ceil((mx.x - mn.x) / cell)) + 1
	var rows := int(ceil((mx.y - mn.y) / cell)) + 1
	var wts := PackedFloat32Array()
	wts.resize(cols * rows)
	wts.fill(1.0)
	var solid := PackedByteArray()
	solid.resize(cols * rows)
	buf = maxf(buf, cell)
	var halo := maxf(buf * 2.0, cell * 2.0)
	for h in hazards:
		var c := to_xy(h["ll"], ref)
		var kind: String = h["kind"]
		var blocked: bool = h["blocked"]
		var r_out := maxf(float(h["r"]), cell * 0.6)
		var r_in := float(h["r_in"])
		var pen := float(h["pen"])
		if air and (kind == "slope" or kind == "rock" or kind == "dune"):
			pen = 1.0
		elif air and kind == "wind":
			pen *= 1.5
		var weight := 1.0 + (pen - 1.0) * pen_scale
		var reach := r_out + (buf + halo if blocked else 0.0)
		var i0 := maxi(0, int(floor((c.x - reach - mn.x) / cell)))
		var i1 := mini(cols - 1, int(ceil((c.x + reach - mn.x) / cell)))
		var j0 := maxi(0, int(floor((c.y - reach - mn.y) / cell)))
		var j1 := mini(rows - 1, int(ceil((c.y + reach - mn.y) / cell)))
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var d := Vector2(mn.x + i * cell, mn.y + j * cell).distance_to(c)
				var idx := j * cols + i
				if blocked:
					var inside := d <= r_out + buf and d >= r_in - buf
					if inside:
						if relax and bool(h["relax"]):
							wts[idx] = maxf(wts[idx], 30.0)
						else:
							solid[idx] = 1
					elif halo_w > 0.0 and d <= r_out + buf + halo and d >= r_in - buf - halo:
						wts[idx] = maxf(wts[idx], 1.0 + halo_w)
				elif d <= r_out and d >= r_in:
					wts[idx] = maxf(wts[idx], weight)

	var s_id := Vector2i(clampi(int(round((a.x - mn.x) / cell)), 0, cols - 1), clampi(int(round((a.y - mn.y) / cell)), 0, rows - 1))
	var t_id := Vector2i(clampi(int(round((b.x - mn.x) / cell)), 0, cols - 1), clampi(int(round((b.y - mn.y) / cell)), 0, rows - 1))
	var warnings: Array = []
	# At coarse scales small keep-outs are inflated to one grid cell. Never let that
	# entomb the start or goal unless they are truly inside a blocked hazard.
	for pair in [[start, s_id], [goal, t_id]]:
		if hazards_at(pair[0], hazards, true).is_empty():
			var c0: Vector2i = pair[1]
			for j in range(maxi(0, c0.y - 3), mini(rows, c0.y + 4)):
				for i in range(maxi(0, c0.x - 3), mini(cols, c0.x + 4)):
					solid[j * cols + i] = 0
	# leaving a restricted area you are already inside: open a small exit pocket
	if solid[s_id.y * cols + s_id.x] == 1:
		var inside_names: Array = []
		for hz in hazards_at(start, hazards, true):
			inside_names.append(hz["name"])
		warnings.append("You are INSIDE restricted ground (%s). Route leads out by the shortest way." % ", ".join(inside_names))
		for j in range(maxi(0, s_id.y - 40), mini(rows, s_id.y + 41)):
			for i in range(maxi(0, s_id.x - 40), mini(cols, s_id.x + 41)):
				if Vector2(i, j).distance_to(Vector2(s_id)) <= 40.0 and solid[j * cols + i] == 1:
					# only open cells that belong to blocked hazards containing the start
					var cell_ll := from_xy(Vector2(mn.x + i * cell, mn.y + j * cell), ref)
					for hz2 in hazards_at(start, hazards, true):
						if hazard_contains(hz2, cell_ll, buf):
							solid[j * cols + i] = 0
							break
	var goal_adjusted := false
	if solid[t_id.y * cols + t_id.x] == 1:
		var found := false
		for rad in range(1, maxi(cols, rows)):
			var best := Vector2i(-1, -1)
			var bd := INF
			for j in range(maxi(0, t_id.y - rad), mini(rows, t_id.y + rad + 1)):
				for i in range(maxi(0, t_id.x - rad), mini(cols, t_id.x + rad + 1)):
					if solid[j * cols + i] == 0:
						var dd := Vector2(i, j).distance_to(Vector2(t_id))
						if dd < bd:
							bd = dd
							best = Vector2i(i, j)
			if best.x >= 0:
				t_id = best
				found = true
				break
		if not found:
			return {}
		goal_adjusted = true
		var names: Array = []
		for hz3 in hazards_at(goal, hazards, true):
			names.append(hz3["name"])
		warnings.append("Destination is inside restricted ground (%s). Route ends at the nearest permitted point." % ", ".join(names))

	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, cols, rows)
	g.cell_size = Vector2.ONE
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for j in range(rows):
		for i in range(cols):
			var k := j * cols + i
			if solid[k] == 1:
				g.set_point_solid(Vector2i(i, j), true)
			elif wts[k] != 1.0:
				g.set_point_weight_scale(Vector2i(i, j), wts[k])
	var ids: Array[Vector2i] = g.get_id_path(s_id, t_id)
	if ids.is_empty():
		return {}
	var pts: Array = []
	for id in ids:
		pts.append(Vector2(id))
	pts = _smooth(pts, wts, solid, cols)
	var path: Array = []
	for q in pts:
		path.append(from_xy(Vector2(mn.x + q.x * cell, mn.y + q.y * cell), ref))
	path[0] = start
	if not goal_adjusted:
		path[path.size() - 1] = goal
	return {"path": path, "goal_adjusted": goal_adjusted, "warnings": warnings}

## Line-of-sight smoothing that never cuts through blocked cells or into costlier ground.
static func _smooth(pts: Array, wts: PackedFloat32Array, solid: PackedByteArray, cols: int) -> Array:
	var n := pts.size()
	if n < 3:
		return pts
	var cum: Array = [0.0]
	for k in range(1, n):
		var seg: float = pts[k - 1].distance_to(pts[k])
		cum.append(float(cum[k - 1]) + seg * (_w(wts, pts[k - 1], cols) + _w(wts, pts[k], cols)) * 0.5)
	var out: Array = [pts[0]]
	var i := 0
	while i < n - 1:
		var next := i + 1
		for j in range(n - 1, i, -1):
			if _los(pts[i], pts[j], wts, solid, cols, (float(cum[j]) - float(cum[i])) * 1.02 + 0.0001):
				next = j
				break
		out.append(pts[next])
		i = next
	return out

static func _w(wts: PackedFloat32Array, p: Vector2, cols: int) -> float:
	return wts[int(round(p.y)) * cols + int(round(p.x))]

static func _los(p: Vector2, q: Vector2, wts: PackedFloat32Array, solid: PackedByteArray, cols: int, budget: float) -> bool:
	var len_c := p.distance_to(q)
	var steps := maxi(1, int(ceil(len_c / 0.5)))
	var step_len := len_c / float(steps)
	var cost := 0.0
	for s in range(steps + 1):
		var r := p.lerp(q, float(s) / float(steps))
		var idx := int(round(r.y)) * cols + int(round(r.x))
		if solid[idx] == 1:
			return false
		cost += wts[idx] * step_len
		if cost > budget + step_len * 4.0:
			return false
	return cost <= budget + step_len

# ------------------------------------------------------------------ analysis
static func _seg_circle_dist(a: Vector2, b: Vector2, c: Vector2) -> float:
	return c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b))

## Blocked hazards that the straight line start->goal would have crossed.
static func _avoided(start: Vector2, goal: Vector2, hazards: Array) -> Array:
	var ref := Vector2((start.x + goal.x) * 0.5, start.y + wrap_dlon(goal.y - start.y) * 0.5)
	var a := to_xy(start, ref)
	var b := to_xy(goal, ref)
	var out: Array = []
	for h in hazards:
		if not bool(h["blocked"]):
			continue
		var c := to_xy(h["ll"], ref)
		var r := float(h["r"])
		var r_in := float(h["r_in"])
		var hit := false
		if r_in > 0.0:
			# ring: crossed if the line passes within the ring band
			var n := 60
			for s in range(n + 1):
				var d := a.lerp(b, float(s) / n).distance_to(c)
				if d <= r and d >= r_in:
					hit = true
					break
		else:
			hit = _seg_circle_dist(a, b, c) <= r
		if hit:
			out.append(h["name"])
	return out

static func _analyze(res: Dictionary, hazards: Array) -> void:
	var path: Array = res["path"]
	var length: float = res["length_km"]
	var samples: Array = []
	var step := maxf(length / 250.0, 0.01)
	var carry := 0.0
	for i in range(path.size() - 1):
		var seg := dist_km(path[i], path[i + 1])
		var d := carry
		while d <= seg:
			samples.append((path[i] as Vector2).lerp(path[i + 1], d / maxf(seg, 0.0001)))
			d += step
		carry = d - seg
	samples.append(path[path.size() - 1])
	var exp_km := {}
	var min_clear := INF
	var min_name := ""
	for p in samples:
		for h in hazards:
			if bool(h["blocked"]):
				var e := edge_dist(h, p)
				if e < min_clear:
					min_clear = e
					min_name = h["name"]
			elif float(h["pen"]) > 1.0 and hazard_contains(h, p):
				exp_km[h["name"]] = float(exp_km.get(h["name"], 0.0)) + step
	var exposure: Array = []
	var total_exp := 0.0
	for k in exp_km:
		exposure.append({"name": k, "km": minf(float(exp_km[k]), length)})
		total_exp += float(exp_km[k])
	res["exposure"] = exposure
	res["min_clear_km"] = min_clear
	res["min_clear_name"] = min_name
	var frac := total_exp / maxf(length, 0.001)
	var risk := "LOW"
	if min_clear < 0.0 or bool(res["relaxed"]):
		risk = "HIGH"
	elif frac > 0.25 or min_clear < 0.05:
		risk = "MODERATE"
	elif frac > 0.05:
		risk = "ELEVATED"
	res["risk"] = risk

# ------------------------------------------------------------------ guidance
static func build_steps(path: Array, hazards: Array, dest_name: String) -> Array:
	var steps: Array = []
	if path.size() < 2:
		return steps
	var cum := 0.0
	var prev_brg := -1.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var leg := dist_km(a, b)
		var brg := bearing(a, b)
		var text := ""
		if i == 0:
			text = "Depart heading %s (%03d°)" % [compass(brg), int(brg)]
		else:
			var turn := wrap_dlon(brg - prev_brg)
			if absf(turn) < 12.0:
				text = "Continue %s" % compass(brg)
			else:
				text = "Turn %s %d° to %s (%03d°)" % ["right" if turn > 0 else "left", int(round(absf(turn))), compass(brg), int(brg)]
		var note := _leg_note(a, b, hazards)
		steps.append({"text": text, "dist_km": leg, "bearing": brg, "at_km": cum, "ll": a, "note": note})
		cum += leg
		prev_brg = brg
	steps.append({"text": "Arrive at %s" % dest_name, "dist_km": 0.0, "bearing": prev_brg, "at_km": cum, "ll": path[path.size() - 1], "note": ""})
	return steps

static func _leg_note(a: Vector2, b: Vector2, hazards: Array) -> String:
	var ref := a
	var pa := Vector2.ZERO
	var pb := to_xy(b, ref)
	var best := ""
	var bd := 0.6
	var side := ""
	for h in hazards:
		if not bool(h["blocked"]) and float(h["pen"]) < 3.0:
			continue
		var c := to_xy(h["ll"], ref)
		var d := _seg_circle_dist(pa, pb, c) - float(h["r"])
		if d < bd:
			bd = d
			best = h["name"]
			var dir := (pb - pa).normalized()
			side = "right" if dir.cross(c - pa) > 0.0 else "left"
	if best == "":
		return ""
	return "%s %s on your %s" % [fmt_dist(maxf(bd, 0.0)) + " from", best, side]

## Cumulative distances along a lat/lon path.
static func cumulative(path: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		out.append(out[i - 1] + dist_km(path[i - 1], path[i]))
	return out

static func point_at(path: Array, cum: PackedFloat32Array, s: float) -> Dictionary:
	var total := cum[cum.size() - 1]
	s = clampf(s, 0.0, total)
	for i in range(path.size() - 1):
		if s <= cum[i + 1] or i == path.size() - 2:
			var seg := maxf(cum[i + 1] - cum[i], 0.0001)
			var t := clampf((s - cum[i]) / seg, 0.0, 1.0)
			return {"ll": (path[i] as Vector2).lerp(path[i + 1], t), "heading": bearing(path[i], path[i + 1]), "leg": i}
	return {"ll": path[path.size() - 1], "heading": 0.0, "leg": path.size() - 2}

## Project a position onto the route: progress along it (km) and cross-track error (km).
static func project(path: Array, cum: PackedFloat32Array, ll: Vector2) -> Dictionary:
	var best := INF
	var best_s := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var pb := to_xy(b, a)
		var pp := to_xy(ll, a)
		var q := Geometry2D.get_closest_point_to_segment(pp, Vector2.ZERO, pb)
		var d := pp.distance_to(q)
		if d < best:
			best = d
			best_s = cum[i] + q.length()
	return {"s": best_s, "cross_km": best}

# ------------------------------------------------------------------ simulated GPS
## Simulated receiver. true_ll is where the vehicle really is; est_ll() is what the
## crew's display shows (true + error). Error grows with distance driven (visual odometry
## drift) and is reset by orbital beacon fixes, which are lost in dust.
class GpsSim extends RefCounted:
	var true_ll := Vector2.ZERO
	var err := Vector2.ZERO          # km, x east / y north
	var since_fix := 0.0             # sim seconds
	var fix_interval := 90.0
	var fix_state := "BEACON FIX"
	var accuracy_m := 6.0
	var rng := RandomNumberGenerator.new()

	func _init() -> void:
		rng.seed = 20260515

	func place(ll: Vector2) -> void:
		true_ll = ll
		err = Vector2.ZERO
		since_fix = 0.0
		fix_state = "BEACON FIX"
		accuracy_m = 6.0

	func est_ll() -> Vector2:
		var c := maxf(cos(deg_to_rad(true_ll.x)), 0.05)
		return Vector2(true_ll.x + err.y / 59.27, fposmod(true_ll.y + err.x / (59.27 * c) + 180.0, 360.0) - 180.0)

	func step(dt_sim: float, moved_km: float, degraded: bool) -> void:
		var drift := moved_km * (0.04 if degraded else 0.008)
		if drift > 0.0:
			err += Vector2.RIGHT.rotated(rng.randf() * TAU) * drift * rng.randf_range(0.5, 1.5)
		since_fix += dt_sim
		if degraded:
			fix_state = "DEAD RECKONING (dust)"
		elif since_fix >= fix_interval:
			err *= 0.15
			since_fix = 0.0
			fix_state = "BEACON FIX"
		elif fix_state.begins_with("DEAD"):
			fix_state = "RECOVERING"
		if err.length() > 0.35:
			err = err.normalized() * 0.35
		accuracy_m = err.length() * 1000.0 + 6.0

	func quality() -> String:
		if accuracy_m <= 30.0:
			return "GOOD"
		if accuracy_m <= 150.0:
			return "FAIR"
		return "POOR"
