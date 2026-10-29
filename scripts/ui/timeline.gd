class_name Timeline
extends RefCounted
## Dalla registrazione della partita (engine.history) ricava cosa mostrare in ogni istante:
## posizioni (anche a metà di un movimento), orientamento, velocità, stato delle pedine ed effetti
## (raggi laser, esplosioni). Lo usano sia la partita in corso sia il replay continuo finale.
##
## Stato restituito: {"units": {id: {"p": Vector2 (coordinate esagonali, lato 1), "a": angolo,
##   "v": vel, "f": bit (1 scoperta, 2 campo di forza, 4 salto, 8 pronta sopra la nave), "al": opacità}},
##  "fx": [effetti], "maps": mappe}


static func duration(seg: Dictionary) -> float:
	match str(seg.get("k", "")):
		"move":
			return 0.35 + 0.16 * int(seg.get("steps", 0))
		"fire":
			return 0.7
		"boom", "launch", "jump":
			return 0.5
		"cmd":
			return 0.35
		"start", "end":
			return 0.3
	return 0.3


static func pos_of(h) -> Vector2:
	return Hex.center(h, 1.0) if h is Vector2i else Vector2.ZERO


static func from_snapshot(snap: Dictionary, reg: Dictionary, maps: Dictionary) -> Dictionary:
	var out := {}
	for id in snap:
		var e: Array = snap[id]
		out[id] = {"p": pos_of(e[0]), "a": Hex.dir_angle(e[1]), "v": e[2], "f": e[3], "al": 1.0, "h": e[0], "d": e[1]}
	_attach(out, reg)
	return {"units": out, "fx": [], "maps": maps}


## le pedine pronte sopra una nave seguono la nave
static func _attach(out: Dictionary, reg: Dictionary) -> void:
	for id in out:
		if int(out[id]["f"]) & 8:
			var host: String = reg.get(id, {}).get("host", "")
			if out.has(host):
				out[id]["p"] = out[host]["p"]
				out[id]["a"] = out[host]["a"]
				out[id]["al"] = out[host]["al"]


static func _lerp_angle(a: float, b: float, t: float) -> float:
	return lerp_angle(a, b, t)


static func state_at(hist: Array, i: int, t: float, reg: Dictionary) -> Dictionary:
	if hist.is_empty():
		return {"units": {}, "fx": [], "maps": {}}
	i = clampi(i, 0, hist.size() - 1)
	t = clampf(t, 0.0, 1.0)
	var seg: Dictionary = hist[i]
	var cur: Dictionary = seg["u"]
	var prev: Dictionary = hist[i - 1]["u"] if i > 0 else cur
	var out := {}
	var fx := []
	var k := str(seg.get("k", ""))
	if k == "move":
		var paths: Dictionary = seg.get("paths", {})
		var steps := maxi(1, int(seg.get("steps", 1)))
		var p := t * steps
		var ids := {}
		for id in prev:
			ids[id] = true
		for id in cur:
			ids[id] = true
		for id in ids:
			var e: Array = cur[id] if cur.has(id) else prev[id]
			var e0: Array = prev[id] if prev.has(id) else e
			if paths.has(id):
				var path: Array = paths[id]
				var n := path.size() - 1
				if not cur.has(id) and p > n + 0.35:
					continue
				var kk := minf(p, float(n))
				var a0 := floori(kk)
				var a1 := mini(a0 + 1, n)
				var f := kk - a0
				var pos := pos_of(path[a0]).lerp(pos_of(path[a1]), f)
				var ang := Hex.dir_angle(e[1]) if (cur.has(id) and p >= n) else Hex.dir_angle(e0[1])
				var al := 1.0
				if not cur.has(id):
					al = clampf(1.0 - (p - n) / 0.35, 0.0, 1.0)
				out[id] = {"p": pos, "a": ang, "v": e[2], "f": e[3], "al": al, "h": path[a1 if f > 0.5 else a0], "d": e[1]}
			else:
				var al := 1.0
				if not cur.has(id):
					al = 1.0 - t
				if not prev.has(id):
					al = t
				out[id] = {"p": pos_of(e[0]), "a": Hex.dir_angle(e[1]), "v": e[2], "f": e[3], "al": al, "h": e[0], "d": e[1]}
		for ev in seg.get("ev", []):
			var st: float = float(ev.get("step", 0)) / steps
			if ev["k"] == "boom":
				fx.append({"k": "boom", "p": pos_of(ev["at"]), "t": (t - st) / 0.35})
			elif ev["k"] == "miss":
				fx.append({"k": "spark", "p": pos_of(ev["at"]), "t": (t - st) / 0.3})
	else:
		var ids := {}
		for id in prev:
			ids[id] = true
		for id in cur:
			ids[id] = true
		for id in ids:
			if cur.has(id) and prev.has(id):
				var a: Array = prev[id]
				var b: Array = cur[id]
				out[id] = {"p": pos_of(a[0]).lerp(pos_of(b[0]), t), "a": _lerp_angle(Hex.dir_angle(a[1]), Hex.dir_angle(b[1]), t),
					"v": b[2] if t > 0.5 else a[2], "f": b[3] if t > 0.5 else a[3], "al": 1.0, "h": b[0], "d": b[1]}
			elif cur.has(id):
				var b: Array = cur[id]
				out[id] = {"p": pos_of(b[0]), "a": Hex.dir_angle(b[1]), "v": b[2], "f": b[3], "al": t, "h": b[0], "d": b[1]}
			else:
				var a: Array = prev[id]
				out[id] = {"p": pos_of(a[0]), "a": Hex.dir_angle(a[1]), "v": a[2], "f": a[3], "al": 1.0 - t, "h": a[0], "d": a[1]}
		match k:
			"fire":
				var pa = _where(seg["a"], cur, prev)
				var pb = _where(seg["t"], cur, prev)
				if pa != null and pb != null:
					fx.append({"k": "beam", "a": pa, "b": pb, "w": seg.get("w", "lb"), "hit": seg.get("hit", false), "t": t})
			"boom":
				fx.append({"k": "boom", "p": pos_of(seg["at"]), "t": t})
			"jump":
				fx.append({"k": "warp", "p": pos_of(seg["at"]), "t": t})
			"launch":
				var pa = _where(seg.get("a", ""), cur, prev)
				if pa != null:
					fx.append({"k": "puff", "p": pa, "t": t})
	_attach(out, reg)
	return {"units": out, "fx": fx, "maps": seg.get("maps", {})}


static func _where(id: String, cur: Dictionary, prev: Dictionary):
	if cur.has(id):
		return pos_of(cur[id][0])
	if prev.has(id):
		return pos_of(prev[id][0])
	return null


## tempi di inizio di ogni segmento (per il replay)
static func starts(hist: Array) -> Array:
	var out := []
	var t := 0.0
	for s in hist:
		out.append(t)
		t += duration(s)
	out.append(t)
	return out
