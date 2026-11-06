class_name DVAI
extends RefCounted
## Avversario artificiale di DeltaVee.
## Ogni fase guarda un passo avanti con precisione (la sequenza di gioco rende prevedibili le posizioni:
## fra il proprio comando e il proprio fuoco il nemico non si muove) e qualche turno più in là in linea
## retta per gli obiettivi (orbita, fuga verso la mappa E, aggancio).
## Livelli: 0 facile (sceglie fra le mosse buone con un po' di caso), 1 normale, 2 difficile.

const D = preload("res://scripts/data/dv_data.gd")

var level := 1
var rng := RandomNumberGenerator.new()


func _init(lv := 1, seed_v := 0) -> void:
	level = lv
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()


func decide(e: DVEngine, s: int, req: Dictionary):
	match str(req.get("type", "")):
		"deploy":
			return _deploy(e, s, req)
		"cmd":
			return _commands(e, s)
		"fire":
			return _fire(e, s)
		"planet":
			return _planet(e, s, req)
		"hitpart":
			return _hitpart(e, s, req)
	return null


# ================================================================ obiettivi

func goal(e: DVEngine, u: Dictionary) -> Dictionary:
	var side: int = u["side"]
	match e.scn:
		2:
			if side == 0:
				return {"k": "escape", "x": int(e.sc["jump_from"]) * 16}
		3:
			if side == 0 and u["cls"] == "Mu":
				return {"k": "orbit", "hex": e.planets[0]}
			if side == 1 and u["kind"] == "ship":
				var mu: Dictionary = e.units["0sB"]
				if mu["st"] == "on":
					return {"k": "rdv", "t": "0sB"}
		4:
			if side == 0 and u["kind"] == "ship" and u["cls"] != "Dagger":
				return {"k": "orbit", "hex": e.planets[0]}
			if side == 1 and u["cls"] == "Clarinet":
				return {"k": "fight", "careful": true}
	return {"k": "fight"}


## importanza di un bersaglio per chi spara (lato s)
func tweight(e: DVEngine, s: int, t: Dictionary) -> float:
	if t["kind"] == "mis":
		return 0.5
	var w := 1.0 if t["kind"] == "ship" else 0.6
	match e.scn:
		2:
			if s == 1:
				w = 2.0 if t["cls"] == "Iota" else 1.2
		3:
			if s == 1 and t["cls"] == "Mu":
				w = 0.8
		4:
			if s == 0:
				w = 2.2 if t["cls"] == "Clarinet" else 0.8
			else:
				w = 1.6 if t["cls"] == "Zeta" else 0.9
	return w


# ================================================================ schieramento

func _deploy(e: DVEngine, s: int, req: Dictionary) -> Dictionary:
	var hx := {}
	var dr := {}
	var taken := {}
	var enemies := []
	for id in e.order:
		var u: Dictionary = e.units[id]
		if u["side"] != s and u["kind"] == "ship":
			enemies.append(u)
	var center := Vector2i.ZERO
	for u in enemies:
		center += u["hex"]
	if not enemies.is_empty():
		center = Vector2i(center.x / enemies.size(), center.y / enemies.size())
	for sh in req["ships"]:
		var best = null
		var bd := 99999.0
		for h in sh["allowed"]:
			if taken.has(h):
				continue
			var d := float(Hex.dist(h, center)) if not enemies.is_empty() else 0.0
			# il federale (scenario 3) si mette all'altezza dei contrabbandieri; gli altri restano compatti
			var score := d + rng.randf() * 0.5
			if score < bd:
				bd = score
				best = h
		hx[sh["id"]] = best
		taken[best] = true
		var u: Dictionary = e.units[sh["id"]]
		var g := goal(e, u)
		var d := int(u["dir"])
		if g["k"] == "orbit":
			d = Hex.dir_to(best, g["hex"])
		elif g["k"] == "escape":
			d = 3
		elif not enemies.is_empty():
			d = Hex.dir_to(best, center)
		dr[sh["id"]] = d
	var v := 0
	var vr: Array = req.get("vrange", [])
	if not vr.is_empty():
		v = 3 if s == 0 else 2
		v = clampi(v, int(vr[0]), int(vr[1]))
	return {"hex": hx, "dir": dr, "v": v}


# ================================================================ comandi

func _commands(e: DVEngine, s: int) -> Dictionary:
	_rc = {}
	var m := {}
	var b := []
	var enemies := e.live_units(1 - s)
	var plans := {}
	# astronavi e caccia
	for u in e.live_units(s, "ship") + e.live_units(s, "bc"):
		if not u.get("alerted", true):
			continue
		var o := _plan_unit(e, u, enemies)
		if not o.is_empty():
			m[u["id"]] = o
			plans[u["id"]] = o
	# comandi di battaglia
	for u in e.live_units(s, "ship"):
		if not u.get("alerted", true):
			continue
		b += _battle(e, u, plans.get(u["id"], {}), enemies, m)
	# missili intelligenti e MIMS (i guidati solo se c'è il comando di battaglia)
	var guided := {}
	for c in b:
		if c["k"] == "guide":
			guided[c["mis"]] = true
	for u in e.live_units(s, "mis"):
		if u["cls"] == "ug":
			continue
		if u["cls"] == "g" and not guided.has(u["id"]):
			continue
		var o := _plan_missile(e, u, enemies)
		if not o.is_empty():
			m[u["id"]] = o
	return {"m": m, "b": b}


## stato dopo un ordine: [esagono, dir, vel, zig]
func _after(u: Dictionary, a: int, t: int, w) -> Array:
	var h: Vector2i = w if w != null else u["hex"]
	var d: int = posmod(int(u["dir"]) + t, 12)
	var z: int = 0 if t != 0 else int(u["zig"])
	return [h, d, clampi(int(u["v"]) + a, 0, 9), z]


func _plan_unit(e: DVEngine, u: Dictionary, enemies: Array) -> Dictionary:
	var g := goal(e, u)
	var o := {}
	# salto (scenario 3)
	if g["k"] == "escape" and u["kind"] == "ship":
		var jp := e.has_pod_type(u, ["jump", "hunter", "ajump"], 1)
		if jp >= 0:
			if int(u["jump"]) == 1:
				if Hex.block(u["hex"]).x >= int(e.sc["jump_from"]):
					return {"j": "jump"}
				return {"j": "abort"}
			var nxt := Hex.path(u["hex"], u["dir"], u["zig"], u["v"])
			var endh: Vector2i = u["hex"] if nxt[0].is_empty() else nxt[0][-1]
			if Hex.block(endh).x >= int(e.sc["jump_from"]) and not u.get("ffon", false):
				return {"j": "prep"}
	if not e.can_maneuver(u):
		return {}
	var lim := e.man_limits(u)
	var n: int = lim["n"]
	var vrm: int = lim["vr"]
	var best := {}
	var best_score := -1e18
	var cands := []
	# il livello cambia quanto si guarda attorno: facile 2 virate e niente scarti, difficile 4 virate
	var tmax := mini(n, [2, 3, 4][clampi(level, 0, 2)])
	for a in range(-vrm, vrm + 1):
		var nv: int = int(u["v"]) + a
		if nv < 0 or nv > 9:
			continue
		for t in range(-tmax, tmax + 1):
			if absi(a) + absi(t) > n:
				continue
			if lim["single"] and t != 0:
				continue
			cands.append([a, t, null])
	# scarto laterale: solo per astronavi e caccia con il ponte intatto
	var can_weave: bool = not lim["single"] and e.part_state(u, "bridge") < 2 and level > 0
	var scored := []
	for c in cands:
		var sc := _score_state(e, u, g, c[0], c[1], null, enemies)
		scored.append([sc, c])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	if can_weave and n >= 1:
		var top := scored.slice(0, 8 if level >= 2 else 4)
		for item in top:
			var c: Array = item[1]
			if absi(c[0]) + absi(c[1]) + 1 > n:
				continue
			for w in Hex.neighbors(u["hex"]):
				if e.is_planet(w) or e.is_asteroid(w):
					continue
				var sc := _score_state(e, u, g, c[0], c[1], w, enemies)
				scored.append([sc, [c[0], c[1], w]])
		scored.sort_custom(func(x, y): return x[0] > y[0])
	if scored.is_empty():
		return {}
	var pick: Array = scored[0][1]
	if level == 0 and scored.size() > 2 and rng.randf() < 0.35:
		pick = scored[rng.randi_range(0, mini(3, scored.size() - 1))][1]
	if pick[0] == 0 and pick[1] == 0 and pick[2] == null:
		return {}
	o["a"] = pick[0]
	o["t"] = pick[1]
	if pick[2] != null:
		o["w"] = pick[2]
	return o


## valutazione di uno stato futuro della propria unità
func _score_state(e: DVEngine, u: Dictionary, g: Dictionary, a: int, t: int, w, enemies: Array) -> float:
	var st := _after(u, a, t, w)
	var cost := e.man_cost(u, a, t, w != null)
	if not e.can_pay(u, cost):
		return -1e17
	var su: Dictionary = u.duplicate()
	su["hex"] = st[0]
	su["dir"] = st[1]
	su["v"] = st[2]
	su["zig"] = st[3]
	var path := Hex.path(st[0], st[1], st[3], st[2])
	var hexes: Array = path[0]
	var endh: Vector2i = st[0] if hexes.is_empty() else hexes[-1]
	var fu: Dictionary = su.duplicate()
	fu["hex"] = endh
	fu["zig"] = path[1]
	var score := 0.0
	# energia
	var bl := e.blocks_left(u)
	var ew := 0.6 if bl > 12 else (1.5 if bl > 5 else 4.0)
	if u["kind"] != "ship":
		ew = 0.5 if e.energy(u) > 8 else 2.0
	score -= cost * ew
	# pericoli lungo il percorso: missili nemici fermi e asteroidi
	for h in hexes:
		if e.is_asteroid(h):
			score -= 6.0 * minf(1.0, st[2] / 10.0) * 3.0
		for m in e.units_at(h):
			if m["side"] != u["side"] and m["kind"] == "mis":
				var rv: int = e.rel_vel(m, su)[0]
				var ch: int = D.INTERCEPT[clampi(int(m["civ"]), 6, 8)][D.icol(rv)]
				score -= 60.0 * minf(1.0, ch / 10.0) * (0.3 if u.get("ffon", false) else 1.0)
	if not e.in_area(endh) and u["kind"] != "ship":
		score -= 5.0
	# fuoco nemico subito (adesso, prima di muovere) e fuoco proprio dopo il movimento
	var careful: bool = g.get("careful", false)
	for t2 in enemies:
		if t2["kind"] == "mis":
			# minaccia esatta: il missile nemico, nel suo prossimo movimento (dopo il nostro), può
			# raggiungere con qualche manovra l'esagono dove ci fermeremo?
			if endh in _mis_reach(e, t2):
				var mm: Dictionary = t2.duplicate()
				var rv: int = e.rel_vel(mm, fu)[0]
				var ch: int = D.INTERCEPT[clampi(int(t2["civ"]), 6, 8)][D.icol(rv)]
				var pr := minf(1.0, ch / 10.0)
				var ffk := 0.25 if (u["kind"] == "ship" and e.ff_class(u) > 0) else 1.0
				score -= 70.0 * pr * ffk
			continue
		if not t2.get("alerted", true):
			continue
		# missili che il nemico può lanciare davanti a sé nel suo prossimo fuoco
		if t2["kind"] == "ship" and _has_missiles(e, t2):
			var spots := {}
			for sp in e.launch_spots(t2):
				spots[sp[0]] = true
			for h in hexes:
				if spots.has(h):
					score -= 22.0 * (0.3 if u.get("ffon", false) else 1.0)
					break
			if Hex.dist(endh, t2["hex"]) <= 2:
				score -= 6.0
			if careful and Hex.dist(endh, _pred(t2)) <= int(t2["v"]) + 5:
				score -= 25.0
		var inc := _exp_fire(e, t2, su)
		score -= inc * (8.0 if careful else 4.0)
		var out := _exp_fire(e, fu, t2)
		score += out * 5.0 * tweight(e, u["side"], t2) * (0.6 if careful else 1.0)
	# obiettivi
	match g["k"]:
		"fight":
			var dmin := 999
			for t2 in enemies:
				if t2["kind"] != "mis" and t2.get("alerted", true):
					dmin = mini(dmin, Hex.dist(endh, _pred(t2)))
			if dmin < 999:
				var want := 9 if g.get("careful", false) else 2
				score -= absf(dmin - want) * 0.6
				# non perdere il contatto (nello scenario 2 a 25 esagoni è pareggio)
				score -= maxf(0.0, dmin - 9) * 2.0
			# troppo veloce = poche manovre
			score -= maxf(0.0, st[2] - (e.mr(u) - 3)) * 0.8
		"orbit":
			score += _orbit_score(e, u, st, g["hex"])
		"escape":
			var gx: int = g["x"]
			var la := Hex.path(endh, st[1], path[1], st[2] * 2)
			var far: Vector2i = endh if la[0].is_empty() else la[0][-1]
			score += (endh.x - int(u["hex"].x)) * 3.0 + (far.x - endh.x) * 1.0
			if endh.x >= gx:
				score += 40.0
			# niente zig-zag verso l'alto o il basso
			score -= absf(Hex.ddiff(st[1], 3)) * 1.5
		"rdv":
			var mu: Dictionary = e.units[g["t"]]
			if st[0] == mu["hex"] and st[1] == mu["dir"] and st[2] == mu["v"]:
				score += 2000.0
			var mp := _pred(mu)
			var dd := Hex.dist(endh, mp)
			score -= dd * 4.0
			score -= absi(st[2] - int(mu["v"])) * (2.0 if dd < 4 else 0.5)
			score -= absi(Hex.ddiff(st[1], mu["dir"])) * (1.5 if dd < 4 else 0.3)
	if level == 0:
		score += rng.randf() * 4.0
	return score


func _has_missiles(e: DVEngine, t: Dictionary) -> bool:
	if t.get("ffon", false):
		return false
	for i in t["pods"].size():
		var p: Dictionary = t["pods"][i]
		if D.PODS[p["t"]]["lp"] and e.pod_state(t, i) < 2:
			for mt in p["ms"]:
				if int(p["ms"][mt]) > 0 and not mt in D.PODS[p["t"]]["prep"]:
					return true
	return not e.prepared_of(t).is_empty()


## posizione prevista di un'unità dopo il suo prossimo movimento (in linea retta)
func _pred(u: Dictionary) -> Vector2i:
	var v: int = u["v"]
	if u["kind"] == "mis" and u["cls"] == "ug":
		v += 1
	var p := Hex.path(u["hex"], u["dir"], u["zig"], v)
	return u["hex"] if p[0].is_empty() else p[0][-1]


## esagoni che un missile può attraversare nel suo prossimo movimento, contando le manovre possibili
## (i non guidati accelerano di 1 e vanno dritti)
var _rc := {}

func _mis_reach(e: DVEngine, m: Dictionary) -> Dictionary:
	var key := "%s|%s|%d|%d|%d" % [m["id"], m["hex"], m["dir"], m["v"], m.get("eu", 0)]
	if _rc.has(key):
		return _rc[key]
	_rc[key] = _mis_reach0(e, m)
	return _rc[key]


func _mis_reach0(e: DVEngine, m: Dictionary) -> Dictionary:
	return _reach_from(e, m["cls"], int(m.get("civ", 7)), m["hex"], int(m["dir"]), int(m["zig"]), int(m["v"]), int(m.get("eu", 0)))


func _reach_from(e: DVEngine, mt: String, civ: int, h: Vector2i, d: int, z: int, v: int, eu: int) -> Dictionary:
	var out := {}
	if mt == "ug":
		for x in Hex.path(h, d, z, mini(9, v + 1))[0]:
			out[x] = true
		return out
	var row: Array = D.MISSILES[mt][clampi(civ, 6, 8)]
	var vrm: int = row[0]
	var mrm: int = row[1]
	var n := mrm - v
	var single := false
	if v >= mrm:
		n = 1
		single = true
	n = mini(n, eu)
	for a in range(-vrm, vrm + 1):
		for t in range(-3, 4):
			if absi(a) + absi(t) > n or (single and t != 0):
				continue
			var nv := clampi(v + a, 0, 9)
			var zz := z if t == 0 else 0
			for x in Hex.path(h, d + t, zz, nv)[0]:
				out[x] = true
	return out


## colpi attesi (somma delle probabilità) che a può mettere a segno su b
func _exp_fire(e: DVEngine, a: Dictionary, b: Dictionary) -> float:
	if a["kind"] == "mis":
		return 0.0
	var tot := 0.0
	var srcs := ["burst"]
	if a["kind"] == "ship":
		for i in a["pods"].size():
			if D.PODS[a["pods"][i]["t"]]["lp"] and e.pod_state(a, i) < 3:
				srcs.append(i)
	for src in srcs:
		var tv: Dictionary = e.target_value(a, src, b)
		var best := 0.0
		for w in e.weapons_of(a, src):
			var ch := e.hit_chance(w, tv["tv"])
			var p := minf(1.0, ch / 10.0)
			best = maxf(best, p - D.FIRE[w]["cost"] * 0.02)
		tot += best
	return tot


func _orbit_score(e: DVEngine, u: Dictionary, st: Array, planet: Vector2i) -> float:
	var h: Vector2i = st[0]
	var d: int = st[1]
	var v: int = st[2]
	var z: int = st[3]
	if h == planet and v == 1:
		return 1000.0
	var vrm := e.vr(u)
	var best := -Hex.dist(h, planet) * 4.0
	for j in range(1, 5):
		var p := Hex.path(h, d, z, v)
		var hs: Array = p[0]
		for k in hs.size():
			if hs[k] == planet:
				var dec := mini(vrm, maxi(1, e.mr(u) - v))
				if v - dec <= 1:
					return 1000.0 / j
				best = maxf(best, 25.0 / j)
		if not hs.is_empty():
			best = maxf(best, -Hex.dist(hs[-1], planet) * (4.0 - j * 0.5) - j * 2.0)
			h = hs[-1]
		z = p[1]
	# velocità adatta alla distanza
	var dist := Hex.dist(st[0], planet)
	var want := clampi(dist / 3, 1, 4)
	best -= absi(v - want) * 2.5
	return best


# ---------------------------------------------------------------- comandi di battaglia

func _battle(e: DVEngine, u: Dictionary, plan: Dictionary, enemies: Array, m: Dictionary) -> Array:
	var out := []
	var n := e.bc_count(u)
	var side: int = u["side"]
	var g := goal(e, u)
	var st := _after(u, int(plan.get("a", 0)), int(plan.get("t", 0)), plan.get("w", null))
	var near := 999
	for t in enemies:
		if t["kind"] != "mis":
			near = mini(near, Hex.dist(st[0], t["hex"]))
	var ffon: bool = u.get("ffon", false)
	# aggancio (scenario 4)
	if g["k"] == "rdv" and n > 0:
		var mu: Dictionary = e.units[g["t"]]
		if st[0] == mu["hex"] and st[1] == mu["dir"] and st[2] == mu["v"]:
			out.append({"s": u["id"], "k": "rdv", "t": mu["id"]})
			n -= 1
	# minaccia dei missili nemici
	var threat := 0
	for t in enemies:
		if t["kind"] == "mis" and Hex.dist(t["hex"], u["hex"]) <= int(t["v"]) + 3:
			threat += 1
	if ffon and threat == 0 and n > 0:
		out.append({"s": u["id"], "k": "ffoff"})
		n -= 1
		ffon = false
	elif not ffon and threat >= 2 and e.ff_class(u) > 0 and n > 0 and e.blocks_left(u) > 3 and g["k"] != "escape":
		out.append({"s": u["id"], "k": "ffon"})
		n -= 1
		ffon = true
		m.erase(u["id"])
	if ffon:
		m.erase(u["id"])
	# lancio dei caccia preparati
	for i in u["pods"].size():
		if n <= 0:
			break
		var p: Dictionary = u["pods"][i]
		if p["t"] != "bcpod" or p["bc"] == "" or e.pod_state(u, i) >= 2:
			continue
		var bc: Dictionary = e.units[p["bc"]]
		if bc["st"] == "prep" and int(bc["prep_at"]) < e.cmd_round and not ffon and near <= 18:
			var hs := Hex.neighbors(st[0])
			var bh: Vector2i = hs[rng.randi_range(0, 5)]
			out.append({"s": u["id"], "k": "launchbc", "pod": i, "hex": bh, "v": maxi(1, st[2]), "dir": st[1]})
			n -= 1
	# guida dei missili guidati in volo
	for mm in e.live_units(side, "mis"):
		if n <= 0:
			break
		if mm["cls"] == "g" and mm.get("host", "") == u["id"] and int(mm["eu"]) > 0 and e.pod_state(u, int(mm["pod"])) < 2:
			out.append({"s": u["id"], "k": "guide", "mis": mm["id"]})
			n -= 1
	# raggio traente
	var tp := e.has_pod_type(u, ["tractor"], 1)
	if tp >= 0 and n > 0:
		var tc := _tractor(e, u, tp, st, g)
		if not tc.is_empty():
			out.append(tc)
			n -= 1
	# preparazione dei missili
	if near <= 22:
		var guard := 0
		while n > 0 and guard < 6:
			guard += 1
			var have := e.prepared_of(u).size()
			var cap := e.missile_pods(u)
			# conta anche quelli già ordinati in questa fase
			for c in out:
				if c["k"] == "prep":
					have += 1
			if have >= cap:
				break
			var choice := {}
			for pref in ["i", "m", "g", "ug"]:
				for i in u["pods"].size():
					var p: Dictionary = u["pods"][i]
					var pd: Dictionary = D.PODS[p["t"]]
					if not pd["lp"] or e.pod_state(u, i) >= 2 or not pref in pd["prep"]:
						continue
					var avail := int(p["ms"].get(pref, 0))
					for c in out:
						if c["k"] == "prep" and int(c["pod"]) == i and c["mt"] == pref:
							avail -= 1
					if avail > 0:
						choice = {"s": u["id"], "k": "prep", "pod": i, "mt": pref}
						break
				if not choice.is_empty():
					break
			if choice.is_empty():
				break
			out.append(choice)
			n -= 1
	# preparazione dei caccia
	for i in u["pods"].size():
		if n <= 0 or near > 20:
			break
		var p: Dictionary = u["pods"][i]
		if p["t"] == "bcpod" and p["bc"] != "" and e.units[p["bc"]]["st"] == "dock" and e.pod_state(u, i) < 2:
			out.append({"s": u["id"], "k": "prepbc", "pod": i})
			n -= 1
	# ricerca attiva
	if n > 0:
		var hidden := 0
		for t in enemies:
			if not t["rev"] and Hex.dist(t["hex"], u["hex"]) <= 6:
				hidden += 1
		if hidden > 0:
			out.append({"s": u["id"], "k": "search"})
	return out


func _tractor(e: DVEngine, u: Dictionary, tp: int, st: Array, g: Dictionary) -> Dictionary:
	var civ: int = u["pods"][tp]["civ"]
	var rr := 6 if civ >= 8 else 4
	var maxc := 2 if civ >= 8 else 1
	if g["k"] == "rdv":
		var mu: Dictionary = e.units[g["t"]]
		if Hex.dist(mu["hex"], u["hex"]) > rr:
			return {}
		var best := {}
		var bs := absi(int(mu["v"]) - st[2]) + absi(Hex.ddiff(mu["dir"], st[1]))
		for a in range(-maxc, maxc + 1):
			for t in range(-maxc, maxc + 1):
				if absi(a) + absi(t) == 0 or absi(a) + absi(t) > maxc:
					continue
				var nv: int = clampi(int(mu["v"]) + a, 0, 9)
				var sc := absi(nv - st[2]) + absi(Hex.ddiff(posmod(int(mu["dir"]) + t, 12), st[1]))
				if sc < bs and e.energy(u) > 2 * e.burn(mu) * (absi(a) + absi(t)) + 20:
					bs = sc
					best = {"s": u["id"], "k": "tractor", "pod": tp, "t": mu["id"], "a": a, "tt": t}
		return best
	# convoglio (scenario 5): gli insorti spingono via le navi dirette al pianeta
	if e.scn == 4 and u["side"] == 1:
		for t in e.live_units(0, "ship"):
			if Hex.dist(t["hex"], u["hex"]) <= rr and Hex.dist(t["hex"], e.planets[0]) <= 6 and int(t["v"]) < 9:
				if e.energy(u) > 2 * e.burn(t) + 20:
					return {"s": u["id"], "k": "tractor", "pod": tp, "t": t["id"], "a": 1, "tt": 0}
	return {}


# ---------------------------------------------------------------- missili

func _plan_missile(e: DVEngine, u: Dictionary, enemies: Array) -> Dictionary:
	if not e.can_maneuver(u):
		return {}
	var lim := e.man_limits(u)
	var n: int = lim["n"]
	var vrm: int = lim["vr"]
	var best := {}
	var bs := _missile_score(e, u, 0, 0, enemies)
	for a in range(-vrm, vrm + 1):
		for t in range(-mini(n, 3), mini(n, 3) + 1):
			if (a == 0 and t == 0) or absi(a) + absi(t) > n:
				continue
			if lim["single"] and t != 0:
				continue
			if absi(a) + absi(t) > int(u["eu"]):
				continue
			var nv: int = int(u["v"]) + a
			if nv < 1 or nv > 9:
				continue
			var sc := _missile_score(e, u, a, t, enemies) - (absi(a) + absi(t)) * 0.4
			if sc > bs:
				bs = sc
				best = {"a": a, "t": t}
	return best


func _missile_score(e: DVEngine, u: Dictionary, a: int, t: int, enemies: Array) -> float:
	var st := _after(u, a, t, null)
	var su: Dictionary = u.duplicate()
	su["dir"] = st[1]
	su["v"] = st[2]
	su["zig"] = st[3]
	var p := Hex.path(st[0], st[1], st[3], st[2])
	var hs: Array = p[0]
	var endh: Vector2i = u["hex"] if hs.is_empty() else hs[-1]
	var score := -20.0
	var side: int = u["side"]
	var civ := clampi(int(u["civ"]), 6, 8)
	var prey_hit := {}
	for h in hs:
		prey_hit[h] = true
	if _hits_prey(e, side, endh, prey_hit):
		return -500.0
	for t2 in enemies:
		if t2["kind"] == "mis" or not t2.get("alerted", true):
			continue
		if e.scn == 3 and side == 1 and t2["cls"] == "Mu":
			continue     # i pirati non vogliono distruggere la preda
		var w := tweight(e, side, t2)
		var ff := 0.45 if (t2["kind"] == "ship" and e.ff_class(t2) > 0) else 1.0
		# 1) nel nostro movimento il nemico sta fermo: lo attraversiamo?
		if t2["hex"] in hs:
			var rv: int = e.rel_vel(su, t2)[0]
			var pr := minf(1.0, D.INTERCEPT[civ][D.icol(rv)] / 10.0)
			score = maxf(score, 100.0 * pr * w * ff)
			continue
		# 2) il nemico, muovendosi dopo di noi, entra nel nostro esagono?
		var tp: Array = Hex.path(t2["hex"], t2["dir"], t2["zig"], t2["v"])[0]
		if endh in tp:
			var mm: Dictionary = su.duplicate()
			mm["hex"] = endh
			var rv2: int = e.rel_vel(mm, t2)[0]
			var pr2 := minf(1.0, D.INTERCEPT[civ][D.icol(rv2)] / 10.0)
			score = maxf(score, 80.0 * pr2 * w * ff)
			continue
		# 3) dal punto d'arrivo, il turno dopo, si può raggiungere dove sarà il nemico?
		var P: Vector2i = tp[-1] if not tp.is_empty() else t2["hex"]
		var eu_left: int = int(u.get("eu", 0)) - absi(a) - absi(t)
		var reach := _reach_from(e, u["cls"], civ, endh, st[1], p[1], st[2], maxi(0, eu_left))
		if reach.has(P):
			score = maxf(score, 45.0 * w * ff)
		else:
			score = maxf(score, (25.0 - Hex.dist(endh, P) * 3.0) * w)
	return score


## scenario 4: i missili pirati non devono colpire il Corco Mu (distruggerlo dà il pareggio)
func _hits_prey(e: DVEngine, side: int, at: Vector2i, cells: Dictionary) -> bool:
	if e.scn != 3 or side != 1:
		return false
	var mu: Dictionary = e.units.get("0sB", {})
	if mu.is_empty() or mu["st"] != "on":
		return false
	if cells.has(mu["hex"]):
		return true
	var mp: Array = Hex.path(mu["hex"], mu["dir"], mu["zig"], mu["v"])[0]
	if at in mp:
		return true
	if not mp.is_empty() and cells.has(mp[-1]):
		return true
	return false


# ================================================================ fuoco

func _fire(e: DVEngine, s: int) -> Dictionary:
	var best := {}
	var bs := 0.0
	var targets := e.valid_targets(s)
	for id in e.fire_budget:
		var u: Dictionary = e.units[id]
		if u["st"] != "on":
			continue
		for src in e.fire_sources(u):
			for t in targets:
				if e.scn == 3 and s == 1 and t["cls"] == "Mu" and e.part_state(t, "engine") == 3:
					continue
				var tv: Dictionary = e.target_value(u, src, t)
				for w in e.weapons_of(u, src):
					var cost := e.fire_cost(u, w)
					if e.energy(u) < cost + _reserve(e, u):
						continue
					var ch := e.hit_chance(w, tv["tv"])
					if ch <= 0:
						continue
					var p := minf(1.0, ch / 10.0)
					var val := p * _hit_value(e, s, t)
					val -= cost * (0.03 if u["kind"] == "ship" else 0.08)
					if val > bs:
						bs = val
						best = {"s": u["id"], "src": src, "w": w, "t": t["id"]}
		# lanci di missili
		for lo in e.launchable(u):
			var r := _best_launch(e, u, lo)
			if r.is_empty():
				continue
			if r["val"] > bs:
				bs = r["val"]
				best = r["ord"]
	# MIMS
	for mm in e.live_units(s, "mis"):
		if mm["cls"] == "m" and not mm.get("mims_used", false):
			var r := _best_mims(e, mm)
			if not r.is_empty() and r["val"] > bs:
				bs = r["val"]
				best = r["ord"]
	if bs < (0.06 if level > 0 else 0.1):
		return {}
	return best


func _reserve(e: DVEngine, u: Dictionary) -> int:
	if u["kind"] != "ship":
		return 4
	return e.burn(u) * 3


func _hit_value(e: DVEngine, s: int, t: Dictionary) -> float:
	if t["kind"] == "mis":
		# un missile si distrugge solo con 2 (o 1 se scoperto) sulla tabella dei colpi
		var near := 99
		for f in e.live_units(s):
			if f["kind"] != "mis":
				near = mini(near, Hex.dist(f["hex"], t["hex"]))
		var threat := 1.0 if near <= int(t["v"]) + 3 else 0.2
		return (0.2 if t["rev"] else 0.1) * 3.0 * threat
	return tweight(e, s, t)


## lancio di un missile: si valuta con precisione, perché fino al movimento del missile il nemico
## farà solo il suo prossimo movimento (dritto, con velocità e direzione che già conosciamo)
func _best_launch(e: DVEngine, u: Dictionary, lo: Dictionary) -> Dictionary:
	var mt: String = lo["mt"]
	var civ: int = clampi(int(u["pods"][lo["pod"]]["civ"]), 6, 8)
	var eu := 0
	if mt != "ug":
		eu = int(D.MISSILES[mt][civ][2])
	var best := {}
	var bv := 0.0
	var enemies := e.valid_targets(u["side"])
	for sp in e.launch_spots(u):
		for d in sp[1]:
			for v in e.launch_vels(u):
				var val := 0.0
				var reach := _reach_from(e, mt, civ, sp[0], d, 0, v, eu)
				if _hits_prey(e, u["side"], sp[0], reach):
					continue
				for t in enemies:
					if t["kind"] == "mis":
						continue
					if e.scn == 3 and u["side"] == 1 and t["cls"] == "Mu":
						continue
					var w := tweight(e, u["side"], t)
					var ff := 0.45 if (t["kind"] == "ship" and e.ff_class(t) > 0) else 1.0
					var tpath: Array = Hex.path(t["hex"], t["dir"], t["zig"], t["v"])[0]
					var P: Vector2i = tpath[-1] if not tpath.is_empty() else t["hex"]
					var mm := {"hex": sp[0], "dir": d, "v": v + (1 if mt == "ug" else 0), "zig": 0, "kind": "mis", "cls": mt}
					var rv: int = e.rel_vel(mm, t)[0]
					var pr := minf(1.0, D.INTERCEPT[civ][D.icol(rv)] / 10.0)
					if sp[0] in tpath:
						# il nemico passa sopra il missile appena lanciato
						val = maxf(val, 0.95 * pr * w * ff)
					elif reach.has(P):
						val = maxf(val, (0.9 if mt == "ug" else 0.8) * pr * w * ff)
				if mt == "m":
					val *= 1.15
				if val > bv:
					bv = val
					best = {"s": u["id"], "src": lo["pod"], "launch": mt, "hex": sp[0], "dir": d, "v": v}
	if best.is_empty():
		return {}
	return {"val": bv, "ord": best}


func _best_mims(e: DVEngine, mm: Dictionary) -> Dictionary:
	var enemies := e.valid_targets(mm["side"])
	var near := 99
	var tgt := {}
	for t in enemies:
		if t["kind"] == "mis":
			continue
		var d := Hex.dist(mm["hex"], t["hex"])
		if d < near:
			near = d
			tgt = t
	if tgt.is_empty() or near > 6:
		return {}
	var tp := _pred(tgt)
	var pl := []
	var spots := e.launch_spots(mm)
	var vels := e.launch_vels(mm)
	var opts := []
	for sp in spots:
		for d in sp[1]:
			for v in vels:
				var hs: Array = Hex.path(sp[0], d, 0, v + 1)[0]
				var sc := 0.0
				if tp in hs or tgt["hex"] in hs:
					sc = 10.0
				else:
					sc = -Hex.dist(hs[-1] if not hs.is_empty() else sp[0], tp)
				opts.append([sc, [sp[0], d, v]])
	opts.sort_custom(func(x, y): return x[0] > y[0])
	for i in 4:
		pl.append(opts[mini(i, opts.size() - 1)][1])
	return {"val": 0.9 * tweight(e, mm["side"], tgt), "ord": {"mims": mm["id"], "pl": pl}}


# ================================================================ pianeti e colpi

func _planet(e: DVEngine, s: int, req: Dictionary) -> Dictionary:
	var u: Dictionary = e.units[req["u"]]
	var g := goal(e, u)
	var lim: Dictionary = req["lim"]
	if g["k"] == "orbit" and u["hex"] == g["hex"]:
		var dec := mini(int(lim["vr"]), int(lim["n"]))
		return {"a": -mini(dec, int(u["v"]) - 1), "t": 0}
	return {"a": 0, "t": 0}


const PART_PRI := {"arsenal": 10, "heavy": 9, "hunter": 9, "light": 7, "bcomm": 7, "jump": 5, "ajump": 5,
	"bcpod": 5, "tractor": 5, "energy": 4, "cargo": 2, "bcargo": 2}


func _hitpart(e: DVEngine, s: int, req: Dictionary) -> String:
	var t: Dictionary = e.units[req["u"]]
	var opts: Array = req["options"]
	var mine: bool = t["side"] == s
	var best: String = opts[0]
	var bv := -1e9
	for p in opts:
		var v := _part_value(e, s, t, p)
		if e.part_state(t, p) == 3 and not (e.scn == 3 and t["cls"] == "Mu" and not mine):
			v = -50.0     # colpire una parte già distrutta non serve
		if mine:
			v = -v
		if v > bv:
			bv = v
			best = p
	return best


func _part_value(e: DVEngine, s: int, t: Dictionary, p: String) -> float:
	var v := 0.0
	if p == "bridge":
		v = 8.0
	elif p == "engine":
		v = 8.5
		if e.scn == 3 and t["cls"] == "Mu":
			v = 20.0
	elif p == "ff":
		v = 3.0 if e.ff_class(t) > 0 else 0.5
	else:
		var pod: Dictionary = t["pods"][int(p.substr(1)) - 1]
		v = float(PART_PRI.get(pod["t"], 1))
		if e.scn == 2 and pod["t"] in ["jump"] and t["side"] == 0:
			v = 14.0
		if e.scn == 4 and D.PODS[pod["t"]].get("cargo", false) and t["side"] == 0:
			v = 12.0
	var st := e.part_state(t, p)
	# i pirati vogliono la preda intera: dopo il motore colpiscono parti già distrutte
	if e.scn == 3 and s == 1 and t["cls"] == "Mu":
		if p == "engine" and st < 3:
			return 40.0
		if st == 3:
			return 60.0
		if p == "bridge":
			return -40.0
		return 1.0
	# meglio far avanzare una parte già danneggiata verso la distruzione
	v += st * 1.5
	return v
