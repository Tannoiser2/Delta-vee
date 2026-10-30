class_name ReplayTrack
extends RefCounted
## Replay continuo e simultaneo: ogni turno di gioco diventa qualche secondo di film in cui TUTTE le unità
## dei due lati si muovono insieme, ognuna alla sua velocità (più esagoni = più veloce), mentre i raggi
## laser, le particelle e i missili partono in tempo reale dalle navi in movimento e inseguono i bersagli.
##
## Nel turno (durata TT):
##   0.00-0.05  comandi del Giocatore 2 (virate, scarti)
##   0.05-0.90  movimento di tutti
##   0.30-0.62  fuoco del Giocatore 1   ·   0.62-0.90  fuoco del Giocatore 2
##   0.90-1.00  comandi del Giocatore 1
## I raggi collegano le posizioni delle navi nell'istante in cui sono mostrati; i missili lanciati escono
## dalla nave che li lancia e raggiungono il loro esagono di lancio entro la fine del movimento.

const TT := 4.0
const START := 1.2

var reg := {}
var keys := {}        # id -> [[t, pos, dir], ...] ordinati
var attrs := {}       # id -> [[t, v, flags], ...]
var life := {}        # id -> [nascita, morte]
var fx: Array = []    # {k, t0, dur, ...}
var mapsev: Array = []   # [[t, maps]]
var labels: Array = []   # [[t, testo]]
var total := 0.0


func _base(turn: int) -> float:
	return START + (maxi(1, turn) - 1) * TT


func build(hist: Array, p_reg: Dictionary) -> void:
	reg = p_reg
	if hist.is_empty():
		return
	# finestre di tempo dei segmenti di fuoco: ogni fase di fuoco è divisa fra i suoi colpi
	var groups := {}
	for i in hist.size():
		var s: Dictionary = hist[i]
		if str(s.get("ph", "")) == "fire":
			var key := "%d|%d" % [int(s["turn"]), int(s["side"])]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(i)
	var win := {}
	for key in groups:
		var parts: PackedStringArray = str(key).split("|")
		var turn := int(parts[0])
		var side := int(parts[1])
		var a := _base(turn) + TT * (0.30 if side == 0 else 0.62)
		var b := _base(turn) + TT * (0.62 if side == 0 else 0.90)
		var idx: Array = groups[key]
		var step := (b - a) / idx.size()
		for j in idx.size():
			win[idx[j]] = [a + j * step, a + j * step + maxf(step, 0.75)]
	var prev: Dictionary = {}
	var births := []
	var last_t := 0.0
	for i in hist.size():
		var s: Dictionary = hist[i]
		var k := str(s.get("k", ""))
		var turn := int(s.get("turn", 0))
		var side := int(s.get("side", 0))
		var ph := str(s.get("ph", ""))
		var base := _base(turn)
		var t0 := 0.0
		var t1 := 0.0
		if turn <= 0 or k == "start":
			t0 = 0.0
			t1 = START * 0.6
		elif k == "end":
			t0 = last_t
			t1 = last_t + 0.5
		elif k == "move":
			t0 = base + TT * 0.05
			t1 = base + TT * 0.90
		elif ph == "cmd" or k == "cmd":
			t0 = base + (0.0 if side == 1 else TT * 0.90)
			t1 = t0 + TT * 0.05 + (0.0 if side == 1 else TT * 0.05)
		elif win.has(i):
			t0 = win[i][0]
			t1 = win[i][1]
		elif ph == "move":
			t0 = base + TT * 0.05
			t1 = t0 + 0.4
		else:
			t0 = base + TT * 0.9
			t1 = t0 + 0.3
		last_t = maxf(last_t, t1)
		var cur: Dictionary = s["u"]
		mapsev.append([t0, s.get("maps", {})])
		labels.append([t0, "Turno %d" % maxi(1, turn) if turn > 0 else "Schieramento"])
		if k == "move":
			var paths: Dictionary = s.get("paths", {})
			var span := t1 - t0
			for id in paths:
				var path: Array = paths[id]
				var n := path.size() - 1
				var e: Array = cur[id] if cur.has(id) else (prev[id] if prev.has(id) else [path[0], 0, 0, 0])
				var vprev: int = int(prev[id][2]) if prev.has(id) else n
				var den := maxi(maxi(n, vprev), 1)
				for j in path.size():
					_key(id, t0 + span * j / den, Timeline.pos_of(path[j]), int(e[1]))
				if not cur.has(id):
					_die(id, t0 + span * n / den)
			for ev in s.get("ev", []):
				var mover := str(ev.get("a", ""))
				var den := 1
				if paths.has(mover):
					den = maxi(paths[mover].size() - 1, 1)
				elif int(s.get("steps", 0)) > 0:
					den = int(s["steps"])
				var tt := t0 + span * float(ev.get("step", 0)) / den
				if ev["k"] == "boom":
					fx.append({"k": "boom", "t0": tt, "dur": 1.0, "at": Timeline.pos_of(ev["at"])})
					var tid := str(ev.get("t", ""))
					if tid != "" and not cur.has(tid):
						_die(tid, tt)
				else:
					fx.append({"k": "spark", "t0": tt, "dur": 0.4, "at": Timeline.pos_of(ev["at"])})
		match k:
			"fire":
				fx.append({"k": "beam", "t0": t0, "dur": maxf(0.75, minf(1.0, t1 - t0)), "a": s["a"], "t": s["t"], "w": s.get("w", "lb"), "hit": s.get("hit", false)})
			"boom":
				fx.append({"k": "boom", "t0": t0 + 0.25, "dur": 1.0, "at": Timeline.pos_of(s["at"])})
			"launch":
				fx.append({"k": "puff", "t0": t0, "dur": 0.4, "id": s.get("a", "")})
			"jump":
				fx.append({"k": "warp", "t0": t0, "dur": 0.8, "at": Timeline.pos_of(s["at"])})
		# nascite, morti e cambi di stato
		for id in cur:
			var e: Array = cur[id]
			if not prev.has(id):
				if not life.has(id):
					life[id] = [t0, INF]
				if k == "launch" or ph == "fire":
					births.append([id, t0, str(s.get("a", "")), e[0], base + TT * 0.90, int(e[1])])
				elif k != "move":
					_key(id, t0, Timeline.pos_of(e[0]), int(e[1]))
			elif k != "move":
				var p: Array = prev[id]
				if p[0] != e[0] or int(p[1]) != int(e[1]):
					_key(id, t0, Timeline.pos_of(p[0]), int(p[1]))
					_key(id, t1, Timeline.pos_of(e[0]), int(e[1]))
			if prev.has(id) and k == "move" and not s.get("paths", {}).has(id):
				var p: Array = prev[id]
				if p[0] != e[0]:
					_key(id, t0, Timeline.pos_of(p[0]), int(p[1]))
					_key(id, t1, Timeline.pos_of(e[0]), int(e[1]))
			_attr(id, t1 if k != "move" else t0, int(e[2]), int(e[3]))
		for id in prev:
			if not cur.has(id) and k != "move":
				_die(id, t0 + (0.45 if k == "boom" else (t1 - t0) * 0.8))
		prev = cur
	for id in keys:
		keys[id].sort_custom(func(a, b): return a[0] < b[0])
	for id in attrs:
		attrs[id].sort_custom(func(a, b): return a[0] < b[0])
	# i missili lanciati escono dalla nave in movimento
	for b in births:
		var id: String = b[0]
		var tb: float = b[1]
		var src: String = b[2]
		var start := Timeline.pos_of(b[3])
		if src != "" and keys.has(src):
			start = pos_at(src, tb)
		var arrive: float = maxf(b[4], tb + 0.4)
		if not keys.has(id):
			keys[id] = []
		keys[id].append([tb, start, b[5]])
		keys[id].append([arrive, Timeline.pos_of(b[3]), b[5]])
		keys[id].sort_custom(func(x, y): return x[0] < y[0])
		life[id] = [tb, life.get(id, [tb, INF])[1]]
	total = last_t + 1.5


func _key(id: String, t: float, p: Vector2, d: int) -> void:
	if not keys.has(id):
		keys[id] = []
	keys[id].append([t, p, d])
	if not life.has(id):
		life[id] = [t, INF]


func _attr(id: String, t: float, v: int, f: int) -> void:
	if not attrs.has(id):
		attrs[id] = []
	var a: Array = attrs[id]
	if not a.is_empty() and int(a[-1][1]) == v and int(a[-1][2]) == f:
		return
	a.append([t, v, f])


func _die(id: String, t: float) -> void:
	if not life.has(id):
		life[id] = [0.0, t]
	else:
		life[id][1] = minf(float(life[id][1]), t)


func pos_at(id: String, t: float) -> Vector2:
	return _sample(id, t)[0]


## [posizione, angolo]
func _sample(id: String, t: float) -> Array:
	var ks: Array = keys.get(id, [])
	if ks.is_empty():
		return [Vector2.ZERO, 0.0]
	if t <= ks[0][0]:
		return [ks[0][1], Hex.dir_angle(ks[0][2])]
	for i in range(1, ks.size()):
		if t < ks[i][0]:
			var a: Array = ks[i - 1]
			var b: Array = ks[i]
			var f := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			var ang := lerp_angle(Hex.dir_angle(a[2]), Hex.dir_angle(b[2]), clampf(f * 3.0, 0.0, 1.0))
			return [Vector2(a[1]).lerp(b[1], f), ang]
	var l: Array = ks[-1]
	return [l[1], Hex.dir_angle(l[2])]


func _attr_at(id: String, t: float) -> Array:
	var a: Array = attrs.get(id, [])
	if a.is_empty():
		return [0, 1]
	var out: Array = a[0]
	for x in a:
		if x[0] <= t:
			out = x
		else:
			break
	return [out[1], out[2]]


func state_at(t: float) -> Dictionary:
	var units := {}
	for id in life:
		var lf: Array = life[id]
		if t < float(lf[0]) or t > float(lf[1]) + 0.3:
			continue
		if not keys.has(id):
			continue
		var smp := _sample(id, t)
		var at := _attr_at(id, t)
		var al := 1.0
		if t > float(lf[1]):
			al = 1.0 - (t - float(lf[1])) / 0.3
		elif t < float(lf[0]) + 0.15:
			al = (t - float(lf[0])) / 0.15
		var p: Vector2 = smp[0]
		units[id] = {"p": p, "a": smp[1], "v": at[0], "f": at[1], "al": clampf(al, 0.0, 1.0),
			"h": Hex.at(p, 1.0), "d": 0}
	Timeline._attach(units, reg)
	var out_fx := []
	for f in fx:
		var tt := (t - float(f["t0"])) / float(f["dur"])
		if tt < 0.0 or tt > 1.0:
			continue
		match f["k"]:
			"beam":
				out_fx.append({"k": "beam", "a": pos_at(f["a"], t), "b": pos_at(f["t"], minf(t, float(life.get(f["t"], [0, INF])[1]))), "w": f["w"], "hit": f["hit"], "t": tt})
			"puff":
				if keys.has(f["id"]):
					out_fx.append({"k": "puff", "p": pos_at(f["id"], t), "t": tt})
			_:
				out_fx.append({"k": f["k"], "p": f["at"], "t": tt})
	var mp := {}
	for m in mapsev:
		if m[0] <= t:
			mp = m[1]
		else:
			break
	return {"units": units, "fx": out_fx, "maps": mp}


func label_at(t: float) -> String:
	var out := ""
	for l in labels:
		if l[0] <= t:
			out = l[1]
		else:
			break
	return out
