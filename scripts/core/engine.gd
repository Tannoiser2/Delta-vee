class_name DVEngine
extends Node
## Motore delle regole di DeltaVee (SPI, 1981), senza dipendenze dalla UI.
## Ogni scelta passa da `decide()`: l'IA risponde subito; per le persone viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo gioca la stessa partita.
##
## Lati: 0 = Giocatore 1 (pedine arancioni), 1 = Giocatore 2 (pedine verdi).
## Unità (units[id]): kind "ship" (astronave), "bc" (caccia Terwillicker), "mis" (missile)
##   hex, dir (0-11 come l'orologio, 0 = ore 12), v (velocità), zig (passo del zig-zag),
##   st: "on" in gioco, "prep" pronto sopra la nave, "dock" nell'hangar, "dead", "jumped", "landed",
##   "orbit" (uscito in orbita, scenario 5), "off" (missile uscito dalla mappa), "spent" (senza energia)
##   rev: scoperta dal nemico (le astronavi lo sono sempre)
##
## Richieste (req["type"]):
##  - "deploy": schieramento con scelte; risposta {"hex": {id: esagono}, "dir": {id: dir}, "v": v}
##  - "cmd": fase di comando; risposta {"m": {id: {"a", "t", "w", "j"}}, "b": [comandi di battaglia]}
##  - "fire": un fuoco o un lancio alla volta; risposta {} per finire
##  - "planet": manovre gratuite entrando in un pianeta; risposta {"a", "t"}
##  - "hitpart": parte colpita a scelta; options = parti, risposta = parte

const D = preload("res://scripts/data/dv_data.gd")

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(result: Dictionary)
signal fx(kind: String, data: Dictionary)

var scn := 0
var sc: Dictionary
var players: Array = []          # [{name, ai, level}]
var ais: Array = [null, null]
var online = null
var ai_delay := 0.6
var anim := 1.0                  # velocità delle animazioni (0 = nessuna attesa)
var headless := false
var abort := false
var rng := RandomNumberGenerator.new()
var max_turns := 40

var units := {}
var order: Array = []
var maps := {}                   # "x,y" -> lettera della mappa
var planets: Array = []
var asteroids := {}              # esagono -> true (campo di asteroidi)
var turn := 0
var phase := ""                  # "move", "cmd", "fire", "setup"
var phasing := 0
var current := 0
var result := {}
var over := false
var log_lines: Array = []
var noint := {}                  # coppie che hanno già fallito l'intercettazione nello stesso esagono
var vp := [0, 0]
var counters := {}               # numerazione delle pedine dei missili per lato
var cmd_round := 0               # contatore delle fasi di comando (per i caccia preparati)
var fire_budget := {}            # fuochi rimasti nella fase di fuoco: id -> {src: n, "x": extra}
var guided_now := {}             # missili guidati con il comando di battaglia in questa fase
var rdv_done := false
var last_roll := 0
var hit_txt: Array = []          # effetti dell'ultimo colpo, per la scritta sulla mappa
## statistiche della partita, per lato (vedi STAT_KEYS) e per unità
var stats: Array = [{}, {}]
var ustats := {}
var _atk := -1                   # lato che sta infliggendo il colpo in corso (-1 = nessuno, es. asteroidi)
var _atk_u := ""                 # unità a cui va il merito del colpo in corso
## salvataggio: decisioni prese finora (var_to_str) e decisioni da rigiocare per riprendere una partita
var dec_log: Array = []
var backlog: Array = []
var resuming := false
signal decided
signal resumed

const STAT_KEYS := ["fires", "hits", "crit", "dmg", "launched", "mhits", "mdown", "kills", "lost", "eu", "dist"]

# registrazione per la vista e il replay
var reg := {}                    # id -> {side, kind, cls, label}
var history: Array = []
var _move_paths := {}
var _move_ev: Array = []


# ================================================================ preparazione

func setup(cfg: Dictionary) -> void:
	scn = int(cfg.get("scenario", 0))
	sc = D.SCENARIOS[scn]
	players = cfg.get("seats", [{"name": "", "ai": false, "level": 1}, {"name": "", "ai": true, "level": 1}])
	if cfg.has("seed"):
		rng.seed = int(cfg["seed"])
	else:
		rng.randomize()
	max_turns = int(cfg.get("max_turns", 40))
	for sd in 2:
		for k in STAT_KEYS:
			stats[sd][k] = 0
	backlog = cfg.get("dec", []).duplicate()
	resuming = not backlog.is_empty()
	ai_delay = float(cfg.get("ai_delay", 0.6))
	anim = float(cfg.get("anim", 1.0))
	var letters: Array = sc["maps"]
	for i in letters.size():
		maps["%d,0" % i] = letters[i]
	for p in sc.get("planet", []):
		planets.append(Hex.parse(p, letters))
	for a in sc.get("asteroids", []):
		var h := Hex.parse(a, letters)
		asteroids[h] = true
		for n in Hex.neighbors(h):
			asteroids[n] = true
	for side in 2:
		for spec in sc["forces"][side]:
			_make_ship(side, spec)


func _make_ship(side: int, spec: Dictionary) -> void:
	var cls: String = spec["cls"]
	var sd: Dictionary = D.SHIPS[cls]
	var id := "%ds%s" % [side, spec["id"]]
	var u := {"id": id, "side": side, "kind": "ship", "cls": cls, "label": spec["id"], "hex": Vector2i.ZERO,
		"dir": int(spec.get("dir", 3)), "v": int(spec.get("v", 0)), "zig": 0, "st": "on", "rev": true,
		"parts": {"bridge": 0, "engine": 0, "ff": 0}, "pods": [], "ffon": false, "jump": 0,
		"alerted": not spec.get("unalerted", false), "spec": spec}
	if spec.has("hex"):
		u["hex"] = Hex.parse(spec["hex"], sc["maps"])
	elif spec.has("near"):
		u["hex"] = Hex.parse(spec["near"], sc["maps"])
	elif spec.has("column"):
		u["hex"] = Hex.parse(spec["column"] + "09", sc["maps"])
	if u["dir"] < 0:
		u["dir"] = 3 if side == 0 else 9
	var cap: int = sd["cap"]
	var nbc := 0
	for pd in spec["pods"]:
		var t: String = pd[0]
		var pdef: Dictionary = D.PODS[t]
		var civ: int = pdef.get("civ", 0)
		if t == "tractor" and pd.size() > 2:
			civ = int(pd[2])
		if civ > sd["civ"]:
			civ -= 1        # [5.3] un modulo più evoluto della nave perde un livello
		var p := {"t": t, "armor": int(pd[1]), "hits": 0, "civ": civ, "ms": {}, "bc": ""}
		if pdef["lp"]:
			for mt in D.MTYPES:
				p["ms"][mt] = int(pdef.get(mt, 0))
			if pd.size() > 2 and str(pd[2]) == "noim":
				p["ms"]["i"] = 0
				p["ms"]["m"] = 0
			if pd.size() > 2 and str(pd[2]) == "nog":
				p["ms"]["g"] = 0
		if t == "energy":
			cap += 144
		if t == "bcpod":
			nbc += 1
			var bid := "%dc%s%d" % [side, spec["id"], nbc]
			var bcls: String = pd[2] if pd.size() > 2 else "TX"
			var b := {"id": bid, "side": side, "kind": "bc", "cls": bcls, "label": "%s%d" % [spec["id"], nbc],
				"hex": u["hex"], "dir": u["dir"], "v": 0, "zig": 0, "st": "dock", "rev": false,
				"parts": {"bridge": 0, "engine": 0}, "eu": 15, "host": id, "pod": u["pods"].size(), "prep_at": -1}
			p["bc"] = bid
			_add_unit(b)
		u["pods"].append(p)
	u["cap"] = cap
	u["spent"] = int(spec.get("spent", 0)) * int(sd["burn"])
	_add_unit(u)


func _add_unit(u: Dictionary) -> void:
	units[u["id"]] = u
	order.append(u["id"])
	reg[u["id"]] = {"side": u["side"], "kind": u["kind"], "cls": u["cls"], "label": u["label"], "host": u.get("host", "")}


# ================================================================ informazioni

func pname(s: int) -> String:
	if s < 0 or s >= players.size():
		return "?"
	var def: String = sc["sides"][s]
	var n: String = str(players[s].get("name", ""))
	return def if n == "" or n == def else "%s (%s)" % [n, def]


func uname(u: Dictionary) -> String:
	match u["kind"]:
		"ship":
			return "%s %s" % [D.SHIPS[u["cls"]]["name"], u["label"]]
		"bc":
			return "caccia %s %s %s" % [D.SHIPS[u["cls"]]["name"], u["label"], D.SIDE_COL[u["side"]]]
	return "%s %s %s" % [D.MNAME_FULL[u["cls"]], u["label"], D.SIDE_COL[u["side"]]]


## nome visto dall'avversario (le pedine coperte non si riconoscono)
func uname_for(u: Dictionary, viewer: int) -> String:
	if u["side"] != viewer and not u["rev"]:
		return "pedina coperta %s" % D.SIDE_COL[u["side"]]
	return uname(u)


func hcode(h: Vector2i) -> String:
	return Hex.code(h, maps)


func sdef(u: Dictionary) -> Dictionary:
	return D.SHIPS[u["cls"]] if u["kind"] != "mis" else {}


func on_map(u: Dictionary) -> bool:
	return u["st"] == "on"


func alive(u: Dictionary) -> bool:
	return u["st"] in ["on", "prep", "dock"]


func live_units(side := -1, kind := "") -> Array:
	var out := []
	for id in order:
		var u: Dictionary = units[id]
		if u["st"] != "on":
			continue
		if side >= 0 and u["side"] != side:
			continue
		if kind != "" and u["kind"] != kind:
			continue
		out.append(u)
	return out


func units_at(h: Vector2i) -> Array:
	var out := []
	for id in order:
		var u: Dictionary = units[id]
		if u["st"] == "on" and u["hex"] == h:
			out.append(u)
	return out


## stato di una parte: 0 intatta, 1 vulnerabile (V), 2 danneggiata (D), 3 distrutta (X)
static func pstate(hits: int, armor: int) -> int:
	if hits <= 0:
		return 0
	if hits >= armor + 1:
		return 3
	if hits == armor:
		return 2
	return 1


func part_armor(u: Dictionary, part: String) -> int:
	if part.begins_with("p"):
		return int(u["pods"][int(part.substr(1)) - 1]["armor"])
	return int(sdef(u)["armor"])


func part_state(u: Dictionary, part: String) -> int:
	if part.begins_with("p"):
		var p: Dictionary = u["pods"][int(part.substr(1)) - 1]
		return pstate(p["hits"], p["armor"])
	return pstate(int(u["parts"].get(part, 0)), part_armor(u, part))


func pod_state(u: Dictionary, i: int) -> int:
	var p: Dictionary = u["pods"][i]
	return pstate(p["hits"], p["armor"])


func part_name(u: Dictionary, part: String) -> String:
	if part.begins_with("p"):
		var i := int(part.substr(1)) - 1
		return "modulo %d (%s)" % [i + 1, D.PODS[u["pods"][i]["t"]]["name"]]
	return D.PART_NAMES[part]


func parts_of(u: Dictionary) -> Array:
	if u["kind"] == "bc":
		return ["bridge", "engine"]
	var out := ["bridge", "engine"]
	if int(sdef(u)["ff"]) > 0:
		out.append("ff")
	for i in u["pods"].size():
		out.append("p%d" % (i + 1))
	return out


func has_pod_type(u: Dictionary, types: Array, max_state := 1) -> int:
	if u["kind"] != "ship":
		return -1
	for i in u["pods"].size():
		if u["pods"][i]["t"] in types and pod_state(u, i) <= max_state:
			return i
	return -1


func bcomm_ok(u: Dictionary) -> bool:
	return has_pod_type(u, ["bcomm"], 1) >= 0


## velocità massima di variazione e capacità di manovra
func vr(u: Dictionary) -> int:
	if u["kind"] == "mis":
		if u["cls"] == "ug":
			return 0
		return int(D.MISSILES[u["cls"]][clampi(int(u["civ"]), 6, 8)][0])
	return int(sdef(u)["vr"])


func mr(u: Dictionary) -> int:
	if u["kind"] == "mis":
		if u["cls"] == "ug":
			return 0
		return int(D.MISSILES[u["cls"]][clampi(int(u["civ"]), 6, 8)][1])
	var b := part_state(u, "bridge")
	if b == 3:
		return 1
	var m: int = sdef(u)["mr"]
	return m - 2 if b == 2 else m


func burn(u: Dictionary) -> int:
	return int(sdef(u)["burn"]) if u["kind"] != "mis" else 1


## energia rimasta in unità
func energy(u: Dictionary) -> int:
	if u["kind"] == "ship":
		return int(u["cap"]) - int(u["spent"])
	return int(u.get("eu", 0))


func blocks_left(u: Dictionary) -> int:
	if u["kind"] == "ship":
		return energy(u) / burn(u)
	return energy(u)


func spend_eu(u: Dictionary, n: int) -> void:
	if u["kind"] == "ship":
		u["spent"] = int(u["spent"]) + n
		_st(u["side"], "eu", n)
	else:
		u["eu"] = maxi(0, int(u.get("eu", 0)) - n)


## campo di forza: classe efficace (0 = inutilizzabile)
func ff_class(u: Dictionary) -> int:
	if u["kind"] != "ship":
		return 0
	var c: int = sdef(u)["ff"]
	if c == 0:
		return 0
	var s := part_state(u, "ff")
	if s == 3:
		return 0
	if c == 1:
		return 0 if s >= 2 else 1
	return 1 if s == 2 else 2


func bc_count(u: Dictionary) -> int:
	if u["kind"] != "ship":
		return 0
	var n := 0
	for i in u["pods"].size():
		var p: Dictionary = u["pods"][i]
		var s := pod_state(u, i)
		if s == 3:
			continue
		if p["t"] in ["light", "heavy", "arsenal"]:
			n += 1
		elif p["t"] == "bcomm":
			n += 1 if s == 2 else 2
	return n


func is_planet(h: Vector2i) -> bool:
	return h in planets


func is_asteroid(h: Vector2i) -> bool:
	return asteroids.has(h)


func in_area(h: Vector2i) -> bool:
	var b := Hex.block(h)
	return maps.has("%d,%d" % [b.x, b.y])


func _add_map(h: Vector2i) -> void:
	var b := Hex.block(h)
	var key := "%d,%d" % [b.x, b.y]
	if maps.has(key):
		return
	# lettere successive: E, F, G…
	var used := maps.values()
	var L := "E"
	for c in "EFGHIJKLMNOPQRSTUVWXYZ":
		if not c in used:
			L = c
			break
	maps[key] = L
	log_msg("Si aggiunge una mappa (%s) al bordo del campo di gioco." % L)


## l'unità può ricevere comandi di manovra?
func can_maneuver(u: Dictionary) -> bool:
	if u["st"] != "on":
		return false
	if u["kind"] == "mis":
		return u["cls"] != "ug" and int(u.get("eu", 0)) > 0
	if part_state(u, "engine") == 3:
		return false
	if u.get("ffon", false) or int(u.get("jump", 0)) > 0:
		return false
	if not u.get("alerted", true):
		return false
	return true


## limiti di manovra: {"n": comandi, "single": solo un accelera/decelera, "vr": variazione massima}
func man_limits(u: Dictionary) -> Dictionary:
	var m := mr(u)
	var v: int = u["v"]
	if v >= m:
		return {"n": 1, "single": true, "vr": mini(1, vr(u))}
	return {"n": m - v, "single": false, "vr": vr(u)}


## costo in energia (unità per caccia e missili, blocchi per le astronavi) di un ordine di manovra
func man_cost(u: Dictionary, a: int, t: int, w: bool) -> int:
	if u["kind"] == "mis":
		return absi(a) + absi(t)
	var n := absi(a) + absi(t)
	if part_state(u, "engine") == 2:
		return n + (1 if w else 0)
	return (1 if n > 1 else 0) + (1 if w else 0)


func can_pay(u: Dictionary, cost: int) -> bool:
	if cost <= 0:
		return true
	if u["kind"] == "ship":
		return energy(u) >= cost * burn(u)
	return energy(u) >= cost


func pay(u: Dictionary, cost: int) -> void:
	if cost <= 0:
		return
	if u["kind"] == "ship":
		spend_eu(u, cost * burn(u))
	else:
		spend_eu(u, cost)


## velocità relativa [8.3] e condizioni [8.4]: restituisce [velocità relativa, gittata dimezzata?]
func rel_vel(a: Dictionary, b: Dictionary) -> Array:
	var va: int = a["v"]
	var vb: int = b["v"]
	var da: int = a["dir"]
	var db: int = b["dir"]
	if da == db and va == vb:
		return [0, true]
	var dd := posmod(db - da, 12)
	var rv := 0
	if dd in [0, 1, 11]:
		rv = absi(va - vb)
	elif dd in [5, 6, 7]:
		rv = va + vb
	else:
		if va == 0 and vb == 0:
			rv = 0
		else:
			rv = D.REL_VEL[maxi(0, mini(vb, 9) - 1)][maxi(0, mini(va, 9) - 1)]
	if posmod(da - db, 6) == 0 and _on_line(a, b["hex"]):
		rv = (rv + 1) / 2
	return [rv, false]


## il bersaglio sta sulla linea di movimento (avanti o indietro) dell'unità?
func _on_line(a: Dictionary, h: Vector2i) -> bool:
	if h == a["hex"]:
		return true
	var d: int = a["dir"]
	for dd in [d, d + 6]:
		var cur: Vector2i = a["hex"]
		var z: int = a["zig"] if dd == d else (1 - int(a["zig"]))
		for i in 30:
			var s := Hex.step(cur, dd, z)
			cur = s[0]
			z = s[1]
			if cur == h:
				return true
	return false


## valore del bersaglio [8.6]: {tv, range, rv, mod}
func target_value(s: Dictionary, src, t: Dictionary) -> Dictionary:
	var rng_h := Hex.dist(s["hex"], t["hex"])
	var r := rel_vel(s, t)
	var rv: int = r[0]
	if r[1]:
		rng_h = (rng_h + 1) / 2
	var mod := int(sdef(s)["tp"])
	if s["kind"] == "ship":
		if src is int and src >= 0:
			var pd: Dictionary = D.PODS[s["pods"][src]["t"]]
			mod = mini(mod, int(pd.get("tp", 0)))
		if bcomm_ok(s) and has_pod_type(s, ["bcomm"], 1) >= 0:
			var bi := has_pod_type(s, ["bcomm"], 1)
			if pod_state(s, bi) < 2:
				mod = mini(mod, -6)
	var rvm := maxi(0, rv + mod)
	return {"tv": rng_h + rvm, "range": rng_h, "rv": rv, "mod": mod}


func hit_chance(w: String, tv: int) -> int:
	var col := D.fire_col(tv)
	if col < 0:
		return 0
	return int(D.FIRE[w]["row"][col])


func d10() -> int:
	last_roll = rng.randi_range(1, 10)
	return last_roll


# ================================================================ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	changed.emit()
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		# stessa forma su tutti i dispositivi (var_to_str ordina le chiavi dei dizionari)
		return str_to_var(var_to_str(r0))
	if not backlog.is_empty():
		var sv: String = backlog.pop_front()
		dec_log.append(sv)
		if backlog.is_empty():
			resuming = false
			resumed.emit()
		return str_to_var(sv)
	var r
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree() and req["type"] in ["cmd", "fire", "deploy"]:
			await get_tree().create_timer(ai_delay).timeout
		r = ais[seat].decide(self, seat, req)
	else:
		decision_requested.emit(req)
		r = await decision_provided
	if abort:
		return r
	# la decisione passa sempre dalla sua forma salvata: così una partita ripresa è identica
	var sv2 := var_to_str(r)
	dec_log.append(sv2)
	decided.emit()
	return str_to_var(sv2)


func _st(side: int, k: String, n := 1) -> void:
	if side >= 0 and side < 2:
		stats[side][k] = int(stats[side][k]) + n


func _ust(id: String, k: String, n := 1) -> void:
	if id == "" or not units.has(id):
		return
	if not ustats.has(id):
		ustats[id] = {"fires": 0, "hits": 0, "dmg": 0, "kills": 0}
	ustats[id][k] = int(ustats[id][k]) + n


func provide_decision(r) -> void:
	decision_provided.emit(r)


func log_msg(t: String) -> void:
	log_lines.append(t)
	log_added.emit(t)


func _pace(sec: float) -> void:
	if headless or anim <= 0.0 or abort or resuming or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	await get_tree().create_timer(sec / anim).timeout


# ================================================================ registrazione

func snapshot() -> Dictionary:
	var out := {}
	for id in order:
		var u: Dictionary = units[id]
		var st: String = u["st"]
		if st == "on":
			var f := (1 if u["rev"] else 0) | (2 if u.get("ffon", false) else 0) | (4 if int(u.get("jump", 0)) > 0 else 0)
			out[id] = [u["hex"], u["dir"], u["v"], f]
		elif st == "prep" and units.has(u.get("host", "")):
			var h: Dictionary = units[u["host"]]
			if h["st"] == "on":
				out[id] = [h["hex"], h["dir"], h["v"], 8]
	return out


func _rec(seg: Dictionary) -> void:
	seg["u"] = snapshot()
	seg["turn"] = turn
	seg["ph"] = phase
	seg["side"] = phasing
	seg["maps"] = maps.duplicate()
	history.append(seg)
	fx.emit(seg["k"], seg)


# ================================================================ partita

func run() -> void:
	phase = "setup"
	log_msg("Scenario %d: %s (%s)." % [scn + 1, sc["name"], sc["orig"]])
	for s in 2:
		await _deploy(s)
		if abort:
			return
	_rec({"k": "start"})
	turn = 1
	while not over and not abort:
		log_msg("— Turno %d —" % turn)
		for pair in [[0, 1], [1, 0]]:
			var a: int = pair[0]
			var b: int = pair[1]
			await _movement(a)
			if over or abort:
				break
			await _command(b)
			if over or abort:
				break
			await _fire(a)
			if over or abort:
				break
		if over or abort:
			break
		_end_turn_checks()
		if over:
			break
		turn += 1
	if abort:
		return
	_finish()


func _finish() -> void:
	phase = "over"
	_rec({"k": "end"})
	changed.emit()
	game_ended.emit(result)


## impronta della partita (per verificare che due dispositivi online abbiano giocato la stessa)
func fingerprint() -> String:
	return "%d|%d|%s" % [turn, log_lines.size(), str(hash(var_to_str(snapshot()) + str(result)))]


func _win(w: int, reason: String) -> void:
	if over:
		return
	over = true
	result = {"winner": w, "reason": reason, "vp": vp.duplicate(), "turn": turn}
	log_msg(("Vince %s: " % pname(w) if w >= 0 else "Pareggio: ") + reason)


# ---------------------------------------------------------------- schieramento

func _deploy(side: int) -> void:
	var ships := []
	var need := false
	for id in order:
		var u: Dictionary = units[id]
		if u["side"] != side or u["kind"] != "ship":
			continue
		var spec: Dictionary = u["spec"]
		var allowed := []
		if spec.has("near"):
			var c := Hex.parse(spec["near"], sc["maps"])
			allowed = [c] + Hex.neighbors(c)
			need = true
		elif spec.has("column"):
			var c0 := Hex.parse(spec["column"] + "01", sc["maps"])
			for r in D.MAP_ROWS:
				allowed.append(Vector2i(c0.x, r))
			need = true
		else:
			allowed = [u["hex"]]
		var dir_free: bool = int(spec.get("dir", 0)) < 0 or sc.has("group_choice")
		if dir_free:
			need = true
		ships.append({"id": id, "allowed": allowed, "dir_free": dir_free})
	var gc = sc.get("group_choice", null)
	var vrange := []
	if gc != null:
		vrange = gc[side]
		need = true
	if not need:
		return
	var req := {"type": "deploy", "ships": ships, "group": gc != null, "vrange": vrange}
	phasing = side
	var r = await decide(side, req)
	if not (r is Dictionary):
		r = {}
	var hx: Dictionary = r.get("hex", {})
	var dr: Dictionary = r.get("dir", {})
	var taken := {}
	for s in ships:
		var u: Dictionary = units[s["id"]]
		var h = hx.get(s["id"], null)
		if not (h is Vector2i) or not h in s["allowed"] or taken.has(h):
			h = null
			for a in s["allowed"]:
				if not taken.has(a):
					h = a
					break
		u["hex"] = h
		taken[h] = true
		if s["dir_free"]:
			var d = dr.get(s["id"], u["dir"])
			if gc != null:
				d = dr.get(ships[0]["id"], u["dir"])
			u["dir"] = posmod(int(d), 12)
		if gc != null:
			u["v"] = clampi(int(r.get("v", 0)), int(vrange[0]), int(vrange[1]))
		for c in _children(u):
			c["hex"] = u["hex"]
			c["dir"] = u["dir"]
	var txt := []
	for s in ships:
		var u: Dictionary = units[s["id"]]
		txt.append("%s in %s (ore %s, vel. %d)" % [uname(u), hcode(u["hex"]), D.DIR_NAMES[u["dir"]], u["v"]])
	log_msg("%s schiera: %s." % [pname(side), "; ".join(txt)])


func _children(u: Dictionary) -> Array:
	var out := []
	for id in order:
		var c: Dictionary = units[id]
		if c.get("host", "") == u["id"] and c["st"] in ["prep", "dock"]:
			out.append(c)
	return out


# ---------------------------------------------------------------- movimento

func _movement(side: int) -> void:
	phase = "move"
	phasing = side
	changed.emit()
	# salti nell'iperspazio ordinati nella fase di comando precedente
	for u in live_units(side, "ship"):
		if int(u["jump"]) == 2:
			u["st"] = "jumped"
			for c in _children(u):
				c["st"] = "jumped"
			log_msg("%s salta nell'iperspazio da %s!" % [uname(u), hcode(u["hex"])])
			_rec({"k": "jump", "id": u["id"], "at": u["hex"]})
			_check_victory()
		elif u.get("land", false):
			u["st"] = "landed"
			log_msg("%s atterra sul pianeta." % uname(u))
			_rec({"k": "land", "id": u["id"]})
	if over:
		return
	_move_paths = {}
	_move_ev = []
	var ids := []
	for k in ["ship", "bc", "mis"]:
		for u in live_units(side, k):
			ids.append(u["id"])
	for id in ids:
		var u: Dictionary = units[id]
		if u["st"] != "on":
			continue
		await _move_unit(u)
		if over or abort:
			break
	# missili senza energia: escono alla fine del movimento
	for u in live_units(side, "mis"):
		if u.get("expire", false):
			u["st"] = "spent"
			log_msg("%s ha esaurito l'energia ed esce dal gioco." % uname_for(u, 1 - side))
	var maxs := 0
	for id in _move_paths:
		maxs = maxi(maxs, _move_paths[id].size() - 1)
	_rec({"k": "move", "paths": _move_paths.duplicate(true), "ev": _move_ev.duplicate(true), "steps": maxs})
	await _pace(0.35 + 0.16 * maxs)
	_cleanup_noint()
	_check_victory()


func _move_unit(u: Dictionary) -> void:
	if u["v"] <= 0:
		return
	if not u.get("alerted", true):
		return
	if u["kind"] != "mis" and is_planet(u["hex"]) and u["v"] == 1:
		return      # in orbita: non si muove
	var path := [u["hex"]]
	var trav := 0
	var remaining: int = u["v"]
	var planet_done := {}
	while remaining > 0 and u["st"] == "on" and not over:
		var s := Hex.step(u["hex"], u["dir"], u["zig"])
		u["hex"] = s[0]
		u["zig"] = s[1]
		trav += 1
		remaining -= 1
		path.append(u["hex"])
		_drag_children(u)
		if not in_area(u["hex"]):
			if u["kind"] == "mis":
				u["st"] = "off"
				break
			_add_map(u["hex"])
		if is_planet(u["hex"]) and not planet_done.has(u["hex"]):
			planet_done[u["hex"]] = true
			if u["kind"] == "mis":
				log_msg("%s si schianta sul pianeta." % uname(u))
				u["st"] = "dead"
				_move_ev.append({"k": "boom", "at": u["hex"], "step": path.size() - 1})
				break
			var newv: int = await _planet(u)
			remaining = newv - trav
		if is_asteroid(u["hex"]):
			await _asteroid(u)
			if u["st"] != "on":
				_move_ev.append({"k": "boom", "at": u["hex"], "step": path.size() - 1})
				break
		await _intercepts_at(u, path.size() - 1)
	_move_paths[u["id"]] = path
	if u["kind"] != "mis":
		_st(u["side"], "dist", path.size() - 1)
	_drag_children(u)


func _drag_children(u: Dictionary) -> void:
	for c in _children(u):
		c["hex"] = u["hex"]
		c["dir"] = u["dir"]
		c["v"] = u["v"]


## [6.5] entrando in un pianeta si possono dare manovre gratuite (non sotto velocità 1)
func _planet(u: Dictionary) -> int:
	if not can_maneuver(u):
		return u["v"]
	var lim := man_limits(u)
	var r = await decide(u["side"], {"type": "planet", "u": u["id"], "lim": lim})
	var a := 0
	var t := 0
	if r is Dictionary:
		a = int(r.get("a", 0))
		t = int(r.get("t", 0))
	a = clampi(a, -int(lim["vr"]), int(lim["vr"]))
	if lim["single"]:
		t = 0
		a = clampi(a, -1, 1)
	while absi(a) + absi(t) > int(lim["n"]):
		if t != 0:
			t -= signi(t)
		else:
			a -= signi(a)
	var nv := clampi(int(u["v"]) + a, 1, 9)
	if nv != u["v"] or t != 0:
		u["v"] = nv
		if t != 0:
			u["dir"] = posmod(int(u["dir"]) + t, 12)
			u["zig"] = 0
		log_msg("%s sfrutta la gravità del pianeta: velocità %d, direzione ore %s." % [uname(u), nv, D.DIR_NAMES[u["dir"]]])
	return u["v"]


## [6.6] asteroidi: con un d10 non superiore alla velocità l'unità è colpita
func _asteroid(u: Dictionary) -> void:
	var r := d10()
	if r > int(u["v"]):
		log_msg("%s attraversa gli asteroidi indenne (dado %d)." % [uname(u), r])
		return
	log_msg("%s è colpito da un asteroide (dado %d)!" % [uname(u), r])
	await _apply_hit(u, d10(), u["side"], true)


# ---------------------------------------------------------------- intercettazione [9.6]

func _pair(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _cleanup_noint() -> void:
	for k in noint.keys():
		var ids: PackedStringArray = k.split("|")
		var a: Dictionary = units.get(ids[0], {})
		var b: Dictionary = units.get(ids[1], {})
		if a.is_empty() or b.is_empty() or a["st"] != "on" or b["st"] != "on" or a["hex"] != b["hex"]:
			noint.erase(k)


## l'unità u è appena entrata nel suo esagono
func _intercepts_at(u: Dictionary, step := -1) -> void:
	var h: Vector2i = u["hex"]
	if u["kind"] == "mis":
		var best: Dictionary = {}
		var best_rv := 999
		for t in units_at(h):
			if t["side"] == u["side"] or noint.has(_pair(u["id"], t["id"])) or not t.get("alerted", true):
				continue
			var rv: int = rel_vel(u, t)[0]
			if rv < best_rv:
				best_rv = rv
				best = t
		if not best.is_empty():
			await _intercept(u, best, step)
			if u["st"] != "on":
				return
	for m in units_at(h):
		if m["kind"] != "mis" or m["side"] == u["side"] or m["st"] != "on" or u["st"] != "on":
			continue
		if noint.has(_pair(u["id"], m["id"])):
			continue
		await _intercept(m, u, step)
		if u["st"] != "on":
			return


func _intercept(m: Dictionary, t: Dictionary, step := -1) -> void:
	var key := _pair(m["id"], t["id"])
	var r := rel_vel(m, t)
	var rv: int = r[0]
	var ch: int = D.INTERCEPT[clampi(int(m["civ"]), 6, 8)][D.icol(rv)]
	var roll := 0 if ch >= 99 else d10()
	m["rev"] = true
	if ch < 99 and roll > ch:
		noint[key] = true
		log_msg("%s manca l'intercettazione di %s (vel. relativa %d, serve %d o meno, dado %d)." % [uname(m), uname_for(t, m["side"]), rv, ch, roll])
		_ev({"k": "miss", "at": t["hex"], "a": m["id"], "t": t["id"], "step": step, "txt": "intercettazione fallita"})
		if step < 0:
			_rec({"k": "dmg", "id": t["id"], "at": t["hex"], "txt": "intercettazione fallita", "bad": false})
		return
	log_msg("%s intercetta %s! (vel. relativa %d, %s)" % [uname(m), uname_for(t, m["side"]), rv, "automatico" if ch >= 99 else "dado %d, serviva %d o meno" % [roll, ch]])
	m["st"] = "dead"
	_ev({"k": "boom", "at": t["hex"], "a": m["id"], "t": t["id"], "step": step, "txt": "INTERCETTATO!"})
	_st(m["side"], "mhits")
	var pa := _atk
	var pu := _atk_u
	_atk = m["side"]
	_atk_u = str(m.get("host", ""))
	await _intercept_hit(m, t, step)
	_atk = pa
	_atk_u = pu


func _intercept_hit(m: Dictionary, t: Dictionary, step: int) -> void:
	if t["kind"] == "ship" and ff_class(t) > 0:
		if not t["ffon"]:
			# [9.8] attivazione d'emergenza del campo di forza
			if part_state(t, "ff") < 2 and can_pay(t, 1):
				var fr := d10()
				if fr <= int(sdef(t)["civ"]) - 2:
					pay(t, 1)
					t["ffon"] = true
					log_msg("%s attiva il campo di forza appena in tempo (dado %d)!" % [uname(t), fr])
				else:
					log_msg("%s non fa in tempo ad attivare il campo di forza (dado %d)." % [uname(t), fr])
		if t["ffon"]:
			var n := 3 if ff_class(t) == 1 else 1
			log_msg("Il campo di forza di %s assorbe l'esplosione: %d tiri sulla tabella dei colpi." % [uname(t), n])
			for i in n:
				if t["st"] != "on":
					break
				await _apply_hit(t, d10(), phasing, false)
			if step < 0:
				_rec({"k": "boom", "at": t["hex"], "id": m["id"]})
				_rec({"k": "dmg", "id": t["id"], "at": t["hex"], "txt": "Campo di forza: colpito", "bad": false})
			return
	_destroy(t, "distrutto dal missile")
	if step < 0:
		_rec({"k": "boom", "at": t["hex"], "id": t["id"]})
		_rec({"k": "dmg", "id": t["id"], "at": t["hex"], "txt": "INTERCETTATO!", "bad": true})


func _ev(e: Dictionary) -> void:
	if phase == "move" and int(e.get("step", -1)) >= 0:
		_move_ev.append(e)


# ---------------------------------------------------------------- colpi [8.7] [8.8] [8.9]

## dado sulla tabella dei colpi; chooser = lato che sceglie la parte (il giocatore di turno)
func _apply_hit(t: Dictionary, roll: int, chooser: int, asteroid := false) -> void:
	if t["kind"] == "mis":
		if roll == 2 or (roll == 1 and t["rev"] and not asteroid):
			log_msg("Colpo (dado %d): %s è distrutto." % [roll, uname(t)])
			hit_txt.append("MISSILE DISTRUTTO")
			t["st"] = "dead"
			if _atk >= 0 and _atk != t["side"]:
				_st(_atk, "mdown")
		else:
			log_msg("Colpo (dado %d): il missile non ne risente." % roll)
			hit_txt.append("nessun effetto")
		return
	var opts := []
	if roll == 1:
		if asteroid:
			log_msg("Colpo critico dell'asteroide: nessun effetto.")
			hit_txt.append("nessun effetto")
			return
		if not t["rev"]:
			log_msg("Colpo critico su una pedina coperta: nessun effetto.")
			hit_txt.append("nessun effetto")
			return
		opts = parts_of(t)
		log_msg("Colpo critico (dado 1)!")
		hit_txt.append("CRITICO!")
		if _atk >= 0:
			_st(_atk, "crit")
	else:
		var have := parts_of(t)
		for p in D.HIT_TABLE[roll]:
			if p in have:
				opts.append(p)
		if opts.is_empty():
			log_msg("Colpo di striscio (dado %d): nessuna parte colpita." % roll)
			hit_txt.append("di striscio")
			return
	var part: String = opts[0]
	if opts.size() > 1:
		var c = await decide(chooser, {"type": "hitpart", "u": t["id"], "options": opts, "roll": roll})
		if c is String and c in opts:
			part = c
	_damage(t, part)


func _damage(t: Dictionary, part: String) -> void:
	var before := part_state(t, part)
	if part.begins_with("p"):
		t["pods"][int(part.substr(1)) - 1]["hits"] += 1
	else:
		t["parts"][part] = int(t["parts"].get(part, 0)) + 1
	var after := part_state(t, part)
	if after > before and _atk >= 0 and _atk != t["side"]:
		_st(_atk, "dmg")
		_ust(_atk_u, "dmg")
	var word: String = ["intatto", "vulnerabile", "danneggiato", "distrutto"][after]
	if before == after:
		word = "già distrutto"
	log_msg("Colpito %s di %s: %s." % [part_name(t, part), uname(t), word])
	var short := D.PART_NAMES.get(part, "") as String
	if part.begins_with("p"):
		short = "modulo %d" % int(part.substr(1))
	hit_txt.append("%s %s" % [short.capitalize(), word])
	if after >= 2 and before < 2 and part.begins_with("p"):
		var i := int(part.substr(1)) - 1
		var p: Dictionary = t["pods"][i]
		if D.PODS[p["t"]]["lp"]:
			for mt in p["ms"]:
				p["ms"][mt] = 0
			for c in _children(t):
				if c["kind"] == "mis" and int(c["pod"]) == i and c["st"] == "prep":
					c["st"] = "dead"
			log_msg("I missili del modulo sono perduti.")
		if p["t"] == "bcpod" and p["bc"] != "":
			var b: Dictionary = units[p["bc"]]
			if b["st"] in ["dock", "prep"]:
				b["st"] = "dead"
				log_msg("Il caccia nell'hangar è perduto.")
		if p["t"] == "energy" and after == 3:
			t["spent"] = maxi(int(t["spent"]), 144)
	if part == "ff" and ff_class(t) == 0 and t.get("ffon", false):
		t["ffon"] = false
		log_msg("Il campo di forza di %s si spegne." % uname(t))
	if part == "engine" and after == 3 and int(t.get("jump", 0)) > 0:
		pass
	# distruzione [11.0]
	if part_state(t, "bridge") == 3 and part_state(t, "engine") == 3:
		if t["kind"] == "bc":
			_destroy(t, "ponte e motore distrutti")
			return
		var dead := 0
		for i in t["pods"].size():
			if pod_state(t, i) == 3:
				dead += 1
		if dead * 2 > t["pods"].size():
			_destroy(t, "ponte, motore e più di metà dei moduli distrutti")


func _destroy(t: Dictionary, why: String) -> void:
	if not alive(t):
		return
	t["st"] = "dead"
	t["ffon"] = false
	if t["kind"] != "mis":
		_st(t["side"], "lost")
		if _atk >= 0 and _atk != t["side"]:
			_st(_atk, "kills")
			_ust(_atk_u, "kills")
	for c in _children(t):
		c["st"] = "dead"
	log_msg("%s è distrutto (%s)!" % [uname(t), why])
	fx.emit("destroyed", {"id": t["id"], "at": t["hex"]})
	_check_victory()


# ---------------------------------------------------------------- comando

func _command(side: int) -> void:
	phase = "cmd"
	phasing = side
	cmd_round += 1
	guided_now = {}
	changed.emit()
	# rilevamento: pedine coperte entro 3 esagoni dalle proprie astronavi e dai caccia
	var eyes := live_units(side, "ship") + live_units(side, "bc")
	for e in live_units(1 - side):
		if e["rev"]:
			continue
		for o in eyes:
			if Hex.dist(o["hex"], e["hex"]) <= 3:
				e["rev"] = true
				log_msg("%s individua %s in %s." % [uname(o), uname(e), hcode(e["hex"])])
				break
	# scenario 4: il Dagger di scorta deve essere allertato
	for u in live_units(side, "ship"):
		if not u.get("alerted", true):
			var r := d10()
			if r <= 2:
				u["alerted"] = true
				log_msg("%s è stato allertato (dado %d) e può entrare in azione!" % [uname(u), r])
			else:
				log_msg("%s non ha ancora ricevuto l'allarme (dado %d)." % [uname(u), r])
	# modulo energia danneggiato: perde 10 unità per fase
	for u in live_units(side, "ship"):
		var ei := -1
		for i in u["pods"].size():
			if u["pods"][i]["t"] == "energy" and pod_state(u, i) == 2:
				ei = i
		if ei >= 0 and int(u["spent"]) < 144:
			u["spent"] = mini(144, int(u["spent"]) + 10)
			log_msg("Il modulo energia danneggiato di %s disperde 10 unità." % uname(u))
	# missili non guidati: +1 di velocità
	for u in live_units(side, "mis"):
		if u["cls"] == "ug":
			u["v"] = mini(9, int(u["v"]) + 1)
	var r = await decide(side, {"type": "cmd", "side": side})
	if abort:
		return
	await _apply_orders(side, r if r is Dictionary else {})
	_rec({"k": "cmd"})
	await _pace(0.35)
	_check_victory()


func _apply_orders(side: int, r: Dictionary) -> void:
	var mo: Dictionary = r.get("m", {})
	var bo: Array = r.get("b", [])
	var used := {}
	# 1) spegnimento dei campi di forza (permette di manovrare nella stessa fase)
	for b in bo:
		if b is Dictionary and str(b.get("k", "")) == "ffoff":
			var s: Dictionary = units.get(str(b.get("s", "")), {})
			if s.is_empty() or s["side"] != side or s["st"] != "on" or not s.get("ffon", false):
				continue
			if int(used.get(s["id"], 0)) >= bc_count(s):
				continue
			used[s["id"]] = int(used.get(s["id"], 0)) + 1
			s["ffon"] = false
			log_msg("%s spegne il campo di forza." % uname(s))
	# 2) comandi di battaglia «guida missile» (servono prima delle manovre dei missili guidati)
	for b in bo:
		if b is Dictionary and str(b.get("k", "")) == "guide":
			var s: Dictionary = units.get(str(b.get("s", "")), {})
			var m: Dictionary = units.get(str(b.get("mis", "")), {})
			if s.is_empty() or m.is_empty() or s["side"] != side or s["st"] != "on" or m["st"] != "on":
				continue
			if m["cls"] != "g" or m.get("host", "") != s["id"]:
				continue
			if pod_state(s, int(m["pod"])) >= 2:
				continue
			if int(used.get(s["id"], 0)) >= bc_count(s):
				continue
			used[s["id"]] = int(used.get(s["id"], 0)) + 1
			guided_now[m["id"]] = true
	# 3) manovre
	for id in mo:
		var u: Dictionary = units.get(str(id), {})
		if u.is_empty() or u["side"] != side or u["st"] != "on":
			continue
		var o = mo[id]
		if o is Dictionary:
			await _maneuver(u, o)
	# jump preparato senza seguito: si annulla
	for u in live_units(side, "ship"):
		if int(u["jump"]) == 1 and int(u.get("jump_at", -1)) < cmd_round:
			u["jump"] = 0
			log_msg("%s annulla il salto." % uname(u))
	# 4) altri comandi di battaglia
	for b in bo:
		if not (b is Dictionary):
			continue
		var k := str(b.get("k", ""))
		if k in ["ffoff", "guide"]:
			continue
		var s: Dictionary = units.get(str(b.get("s", "")), {})
		if s.is_empty() or s["side"] != side or s["st"] != "on" or s["kind"] != "ship":
			continue
		if int(used.get(s["id"], 0)) >= bc_count(s):
			continue
		if not s.get("alerted", true):
			continue
		if s.get("ffon", false) and not k in ["prep", "search", "prepbc"]:
			continue
		if await _battle_cmd(s, k, b):
			used[s["id"]] = int(used.get(s["id"], 0)) + 1
		if over:
			return
	# missili che hanno finito l'energia
	for u in live_units(side, "mis"):
		if u["cls"] != "ug" and int(u.get("eu", 0)) <= 0:
			u["expire"] = true


func _maneuver(u: Dictionary, o: Dictionary) -> void:
	var a := int(o.get("a", 0))
	var t := int(o.get("t", 0))
	var w = o.get("w", null)
	var j := str(o.get("j", ""))
	if u["kind"] == "ship" and j != "":
		_jump_order(u, j)
	if a == 0 and t == 0 and w == null:
		return
	if u["kind"] == "mis":
		if u["cls"] == "ug" or (u["cls"] == "g" and not guided_now.has(u["id"])):
			return
		w = null
	if not can_maneuver(u):
		return
	var lim := man_limits(u)
	a = clampi(a, -int(lim["vr"]), int(lim["vr"]))
	if lim["single"]:
		t = 0
		w = null
		a = clampi(a, -1, 1)
	if w != null:
		if not (w is Vector2i) or Hex.dist(w, u["hex"]) != 1 or is_planet(w) or is_asteroid(w) or u["kind"] == "mis" or part_state(u, "bridge") >= 2:
			w = null
	var n := absi(a) + absi(t) + (1 if w != null else 0)
	while n > int(lim["n"]):
		if w != null:
			w = null
		elif t != 0:
			t -= signi(t)
		else:
			a -= signi(a)
		n = absi(a) + absi(t) + (1 if w != null else 0)
	# energia: se non basta si rinuncia a pezzi
	while not can_pay(u, man_cost(u, a, t, w != null)):
		if w != null:
			w = null
		elif absi(a) + absi(t) > 1:
			if t != 0:
				t -= signi(t)
			else:
				a -= signi(a)
		elif part_state(u, "engine") == 2 or u["kind"] == "mis":
			a = 0
			t = 0
		else:
			break
	if a == 0 and t == 0 and w == null:
		return
	pay(u, man_cost(u, a, t, w != null))
	var nv := clampi(int(u["v"]) + a, 0, 9)
	u["v"] = nv
	if t != 0:
		u["dir"] = posmod(int(u["dir"]) + t, 12)
		u["zig"] = 0
	var bits := []
	if a != 0:
		bits.append("%s di %d (velocità %d)" % ["accelera" if a > 0 else "decelera", absi(a), nv])
	if t != 0:
		bits.append("vira di %d verso ore %s" % [absi(t), D.DIR_NAMES[u["dir"]]])
	if w != null:
		u["hex"] = w
		bits.append("scarta in %s" % hcode(w))
	_drag_children(u)
	if u["kind"] == "mis" and u["side"] != current:
		pass
	log_msg("%s %s." % [uname_for(u, 1 - u["side"]) if u["kind"] != "ship" else uname(u), ", ".join(bits)])
	if w != null:
		await _intercepts_at(u)
	if u["kind"] == "mis" and int(u.get("eu", 0)) <= 0:
		u["expire"] = true
	# orbita e pianeti: atterraggio
	if u["kind"] != "mis" and is_planet(u["hex"]) and nv == 0 and bool(sdef(u)["stream"]):
		u["land"] = true


func _jump_order(u: Dictionary, j: String) -> void:
	var allowed: bool = sc.has("jump_from") and u["side"] == 0
	var pi := has_pod_type(u, ["jump", "hunter", "ajump"], 1)
	if j == "abort":
		if int(u["jump"]) > 0:
			u["jump"] = 0
			log_msg("%s annulla il salto." % uname(u))
		return
	if not allowed or pi < 0:
		return
	var aug: bool = u["pods"][pi]["t"] == "ajump"
	if j == "prep" and int(u["jump"]) == 0:
		if aug:
			j = "jump"
		else:
			u["jump"] = 1
			u["jump_at"] = cmd_round
			log_msg("%s prepara il salto nell'iperspazio." % uname(u))
			return
	if j == "jump" and (int(u["jump"]) == 1 or aug):
		if u.get("ffon", false):
			return
		if Hex.block(u["hex"]).x < int(sc.get("jump_from", 0)):
			log_msg("%s non può ancora saltare: deve raggiungere la mappa E." % uname(u))
			return
		u["jump"] = 2
		log_msg("%s avvia il salto: lascerà il campo di gioco nel prossimo movimento." % uname(u))


## un comando di battaglia; restituisce true se è stato eseguito (e consuma un comando)
func _battle_cmd(s: Dictionary, k: String, b: Dictionary) -> bool:
	match k:
		"prep":
			var pi := int(b.get("pod", -1))
			var mt := str(b.get("mt", ""))
			if pi < 0 or pi >= s["pods"].size() or pod_state(s, pi) >= 2:
				return false
			var p: Dictionary = s["pods"][pi]
			var pd: Dictionary = D.PODS[p["t"]]
			if not pd["lp"] or not mt in pd["prep"] or int(p["ms"].get(mt, 0)) <= 0:
				return false
			if prepared_of(s).size() >= missile_pods(s):
				return false
			p["ms"][mt] = int(p["ms"][mt]) - 1
			var m := _new_missile(s, pi, mt)
			m["st"] = "prep"
			log_msg("%s prepara un %s." % [uname(s), D.MNAME_FULL[mt].to_lower()])
			return true
		"search":
			var rr := 10 if bcomm_ok(s) and pod_state(s, has_pod_type(s, ["bcomm"], 1)) < 2 else 6
			var n := 0
			for e in live_units(1 - s["side"]):
				if not e["rev"] and Hex.dist(s["hex"], e["hex"]) <= rr:
					e["rev"] = true
					n += 1
			log_msg("%s esegue una ricerca attiva (raggio %d): %d pedine scoperte." % [uname(s), rr, n])
			return true
		"prepbc":
			var pi := int(b.get("pod", -1))
			if pi < 0 or pi >= s["pods"].size() or s["pods"][pi]["t"] != "bcpod" or pod_state(s, pi) >= 2:
				return false
			var bid: String = s["pods"][pi]["bc"]
			if bid == "" or units[bid]["st"] != "dock":
				return false
			var bc: Dictionary = units[bid]
			bc["st"] = "prep"
			bc["prep_at"] = cmd_round
			log_msg("%s prepara al lancio il caccia %s." % [uname(s), bc["label"]])
			return true
		"launchbc":
			var pi := int(b.get("pod", -1))
			if pi < 0 or pi >= s["pods"].size() or s["pods"][pi]["t"] != "bcpod" or pod_state(s, pi) >= 2:
				return false
			var bid: String = s["pods"][pi]["bc"]
			if bid == "":
				return false
			var bc: Dictionary = units[bid]
			if bc["st"] != "prep" or int(bc["prep_at"]) >= cmd_round:
				return false
			var h = b.get("hex", null)
			var v := int(b.get("v", s["v"]))
			var d := int(b.get("dir", s["dir"]))
			if not (h is Vector2i) or Hex.dist(h, s["hex"]) != 1:
				return false
			v = clampi(v, maxi(1, int(s["v"]) - 1), maxi(1, int(s["v"]) + 1))
			if absi(Hex.ddiff(s["dir"], d)) > 2:
				d = s["dir"]
			bc["st"] = "on"
			bc["hex"] = h
			bc["v"] = mini(v, 9)
			bc["dir"] = posmod(d, 12)
			bc["zig"] = 0
			bc["rev"] = false
			log_msg("%s lancia il caccia %s." % [uname(s), bc["label"]])
			await _intercepts_at(bc)
			return true
		"dock":
			var bc: Dictionary = units.get(str(b.get("bc", "")), {})
			if bc.is_empty() or bc["st"] != "on" or bc.get("host", "") != s["id"]:
				return false
			if bc["hex"] != s["hex"] or bc["v"] != s["v"] or bc["dir"] != s["dir"]:
				return false
			if pod_state(s, int(bc["pod"])) >= 2:
				return false
			bc["st"] = "dock"
			var need: int = 15 - int(bc["eu"])
			var give := mini(need, energy(s))
			bc["eu"] = int(bc["eu"]) + give
			spend_eu(s, give)
			log_msg("Il caccia %s rientra nell'hangar di %s e fa il pieno." % [bc["label"], uname(s)])
			return true
		"rdv":
			var t: Dictionary = units.get(str(b.get("t", "")), {})
			if t.is_empty() or t["st"] != "on" or t["kind"] != "ship" or t["id"] == s["id"]:
				return false
			if t["hex"] != s["hex"] or t["v"] != s["v"] or t["dir"] != s["dir"]:
				return false
			log_msg("%s si aggancia a %s!" % [uname(s), uname(t)])
			if scn == 3 and s["side"] == 1 and t["cls"] == "Mu":
				rdv_done = true
				_check_victory()
			return true
		"tractor":
			var pi := int(b.get("pod", -1))
			if pi < 0 or pi >= s["pods"].size() or s["pods"][pi]["t"] != "tractor" or pod_state(s, pi) >= 2:
				return false
			var civ: int = s["pods"][pi]["civ"]
			var t: Dictionary = units.get(str(b.get("t", "")), {})
			if t.is_empty() or t["st"] != "on" or t["kind"] == "mis":
				return false
			if Hex.dist(t["hex"], s["hex"]) > (6 if civ >= 8 else 4):
				return false
			var a := int(b.get("a", 0))
			var tt := int(b.get("tt", 0))
			var maxc := 2 if civ >= 8 else 1
			while absi(a) + absi(tt) > maxc:
				if tt != 0:
					tt -= signi(tt)
				else:
					a -= signi(a)
			var n := absi(a) + absi(tt)
			if n == 0:
				return false
			var cost := 2 * burn(t) * n
			if energy(s) < cost:
				return false
			spend_eu(s, cost)
			t["v"] = clampi(int(t["v"]) + a, 0, 9)
			if tt != 0:
				t["dir"] = posmod(int(t["dir"]) + tt, 12)
				t["zig"] = 0
			_drag_children(t)
			log_msg("Il raggio traente di %s afferra %s: velocità %d, direzione ore %s." % [uname(s), uname_for(t, s["side"]), t["v"], D.DIR_NAMES[t["dir"]]])
			return true
		"ffon":
			if s.get("ffon", false) or ff_class(s) == 0 or not can_pay(s, 1):
				return false
			pay(s, 1)
			s["ffon"] = true
			log_msg("%s attiva il campo di forza." % uname(s))
			return true
	return false


func prepared_of(s: Dictionary) -> Array:
	var out := []
	for c in _children(s):
		if c["kind"] == "mis" and c["st"] == "prep":
			out.append(c)
	return out


func missile_pods(s: Dictionary) -> int:
	var n := 0
	for i in s["pods"].size():
		if D.PODS[s["pods"][i]["t"]]["lp"] and pod_state(s, i) < 3:
			n += 1
	return n


func _new_missile(s: Dictionary, pi: int, mt: String) -> Dictionary:
	var side: int = s["side"]
	var key := "%d%s" % [side, mt]
	if mt == "g":
		key += s["label"]
	var n := int(counters.get(key, 0)) + 1
	counters[key] = n
	var label := ""
	match mt:
		"g":
			label = "%s-%02d" % [s["label"], n]
		"i":
			label = "%d" % (20 + n)
		"m":
			label = "%d" % (30 + n)
		_:
			label = "%02d" % n
	var id := "%dm%s%s" % [side, mt, label]
	while units.has(id):
		id += "'"
	var civ: int = s["pods"][pi]["civ"] if pi >= 0 else int(s.get("civ", 7))
	var eu := 0
	if mt != "ug":
		eu = int(D.MISSILES[mt][clampi(civ, 6, 8)][2])
	var m := {"id": id, "side": side, "kind": "mis", "cls": mt, "label": label, "hex": s["hex"], "dir": s["dir"],
		"v": s["v"], "zig": 0, "st": "prep", "rev": false, "civ": civ, "eu": eu, "host": s["id"], "pod": pi}
	_add_unit(m)
	return m


# ---------------------------------------------------------------- fuoco

func _fire(side: int) -> void:
	phase = "fire"
	phasing = side
	fire_budget = {}
	for u in live_units(side, "ship") + live_units(side, "bc"):
		if not u.get("alerted", true):
			continue
		var b := {"burst": 1}
		if u["kind"] == "ship":
			for i in u["pods"].size():
				var p: Dictionary = u["pods"][i]
				var pd: Dictionary = D.PODS[p["t"]]
				var st := pod_state(u, i)
				if pd["lp"] and st < 3:
					b[i] = 1 if (st == 2 and p["t"] == "arsenal") else int(pd["fires"])
			b["x"] = 1 if bcomm_ok(u) and pod_state(u, has_pod_type(u, ["bcomm"], 1)) < 2 else 0
		fire_budget[u["id"]] = b
	changed.emit()
	var guard := 0
	while not over and not abort and guard < 80:
		guard += 1
		if not _any_fire(side):
			break
		var r = await decide(side, {"type": "fire", "side": side})
		if abort:
			return
		if not (r is Dictionary) or r.is_empty():
			break
		var ok := false
		if r.has("mims"):
			ok = await _mims(side, r)
		elif r.has("launch"):
			ok = await _launch(side, r)
		else:
			ok = await _shoot(side, r)
		if not ok:
			guard += 10
		changed.emit()
	_check_victory()


## fuochi ancora disponibili per una sorgente; usa l'extra delle comunicazioni di battaglia
func src_available(u: Dictionary, src) -> bool:
	var b: Dictionary = fire_budget.get(u["id"], {})
	if b.is_empty():
		return false
	if int(b.get(src, 0)) > 0:
		return true
	return b.has(src) and int(b.get("x", 0)) > 0


func _use_src(u: Dictionary, src) -> void:
	var b: Dictionary = fire_budget[u["id"]]
	if int(b.get(src, 0)) > 0:
		b[src] = int(b[src]) - 1
	else:
		b["x"] = int(b.get("x", 0)) - 1


## armi utilizzabili da una sorgente
func weapons_of(u: Dictionary, src) -> Array:
	if str(src) == "burst":
		return ["lb", "lbb"] if int(sdef(u)["burst"]) >= 2 else ["lb"]
	var i := int(src)
	if u["kind"] != "ship" or i < 0 or i >= u["pods"].size():
		return []
	var st := pod_state(u, i)
	if not D.PODS[u["pods"][i]["t"]]["lp"] or st >= 3:
		return []
	return ["lb", "pb"] if st == 2 else ["lb", "lbb", "pb", "pbb"]


func fire_sources(u: Dictionary) -> Array:
	var out := []
	var b: Dictionary = fire_budget.get(u["id"], {})
	for k in b:
		if str(k) == "x":
			continue
		if src_available(u, k):
			out.append(k)
	return out


func valid_targets(side: int) -> Array:
	var out := []
	for t in live_units(1 - side):
		if t.get("alerted", true):
			out.append(t)
	return out


func _any_fire(side: int) -> bool:
	for id in fire_budget:
		var u: Dictionary = units[id]
		if u["st"] != "on":
			continue
		if not fire_sources(u).is_empty() and not valid_targets(side).is_empty():
			return true
		if not launchable(u).is_empty():
			return true
	for m in live_units(side, "mis"):
		if m["cls"] == "m" and not m.get("mims_used", false):
			return true
	return false


func fire_cost(u: Dictionary, w: String) -> int:
	return int(D.FIRE[w]["cost"])


func _shoot(side: int, r: Dictionary) -> bool:
	var u: Dictionary = units.get(str(r.get("s", "")), {})
	var t: Dictionary = units.get(str(r.get("t", "")), {})
	var src = r.get("src", "burst")
	if src is float:
		src = int(src)
	var w := str(r.get("w", "lb"))
	if u.is_empty() or t.is_empty() or u["side"] != side or u["st"] != "on" or t["st"] != "on" or t["side"] == side:
		return false
	if not t.get("alerted", true) or not src_available(u, src) or not w in weapons_of(u, src):
		return false
	var cost := fire_cost(u, w)
	if energy(u) < cost:
		return false
	_use_src(u, src)
	spend_eu(u, cost)
	_st(side, "fires")
	_ust(u["id"], "fires")
	var tv := target_value(u, src, t)
	var ch := hit_chance(w, tv["tv"])
	var srcname := "burster" if str(src) == "burst" else "modulo %d" % (int(src) + 1)
	var desc := "%s (%s) spara %s a %s: gittata %d, vel. relativa %d%s = valore %d" % [
		uname(u), srcname, D.FIRE[w]["art"], uname_for(t, side), tv["range"], tv["rv"],
		(", puntamento %d" % tv["mod"]) if tv["mod"] != 0 else "", tv["tv"]]
	if ch <= 0:
		log_msg(desc + ": colpo impossibile.")
		_rec({"k": "fire", "a": u["id"], "t": t["id"], "w": w, "hit": false})
		await _pace(1.0)
		return true
	var hit := true
	var roll := 0
	if ch < 99:
		roll = d10()
		hit = roll <= ch
	log_msg(desc + (", serve %d o meno, dado %d: " % [ch, roll] if ch < 99 else ", colpo automatico: ") + ("COLPITO!" if hit else "mancato."))
	_rec({"k": "fire", "a": u["id"], "t": t["id"], "w": w, "hit": hit, "roll": roll, "need": ch})
	await _pace(1.0)
	if hit:
		_st(side, "hits")
		_ust(u["id"], "hits")
		hit_txt = []
		_atk = side
		_atk_u = u["id"]
		await _apply_hit(t, d10(), side)
		_atk = -1
		_atk_u = ""
		if t["st"] == "dead":
			_rec({"k": "boom", "at": t["hex"], "id": t["id"]})
			_rec({"k": "dmg", "id": t["id"], "at": t["hex"], "txt": "DISTRUTTO!", "bad": true})
			await _pace(1.0)
		else:
			_rec({"k": "dmg", "id": t["id"], "at": t["hex"], "txt": ", ".join(hit_txt), "bad": false})
			await _pace(0.8)
	return true


## esagoni e direzioni di lancio [9.4] per un'unità (astronave o MIMS): [[esagono, [direzioni]]…]
func launch_spots(u: Dictionary) -> Array:
	var d: int = u["dir"]
	var h: Vector2i = u["hex"]
	var out := []
	if d % 2 == 0:
		out.append([Hex.side_step(h, d - 2), [posmod(d - 2, 12), posmod(d - 1, 12), d]])
		out.append([Hex.side_step(h, d), [posmod(d - 1, 12), d, posmod(d + 1, 12)]])
		out.append([Hex.side_step(h, d + 2), [d, posmod(d + 1, 12), posmod(d + 2, 12)]])
	else:
		var ds := [posmod(d - 1, 12), d, posmod(d + 1, 12)]
		out.append([Hex.side_step(h, d - 1), ds])
		out.append([Hex.side_step(h, d + 1), ds])
	return out


func launch_vels(u: Dictionary) -> Array:
	var out := []
	for dv in [-1, 0, 1]:
		var v: int = int(u["v"]) + dv
		if v >= 1 and v <= 9 and not v in out:
			out.append(v)
	if out.is_empty():
		out.append(1)
	return out


## missili lanciabili ora da un'astronave: [{pod, mt, mis (id del preparato o "")}]
func launchable(u: Dictionary) -> Array:
	var out := []
	if u["kind"] != "ship" or u["st"] != "on" or u.get("ffon", false):
		return out
	for i in u["pods"].size():
		var p: Dictionary = u["pods"][i]
		var pd: Dictionary = D.PODS[p["t"]]
		if not pd["lp"] or pod_state(u, i) >= 2 or not src_available(u, i):
			continue
		for mt in D.MTYPES:
			if mt in pd["prep"]:
				for c in prepared_of(u):
					if int(c["pod"]) == i and c["cls"] == mt:
						out.append({"pod": i, "mt": mt, "mis": c["id"]})
						break
			elif int(p["ms"].get(mt, 0)) > 0:
				out.append({"pod": i, "mt": mt, "mis": ""})
	return out


func _launch(side: int, r: Dictionary) -> bool:
	var u: Dictionary = units.get(str(r.get("s", "")), {})
	if u.is_empty() or u["side"] != side:
		return false
	var opt := {}
	for o in launchable(u):
		if int(o["pod"]) == int(r.get("src", -1)) and o["mt"] == str(r.get("launch", "")):
			opt = o
			break
	if opt.is_empty():
		return false
	var h = r.get("hex", null)
	var d := int(r.get("dir", u["dir"]))
	var v := int(r.get("v", u["v"]))
	var ok := false
	for sp in launch_spots(u):
		if sp[0] == h and d in sp[1]:
			ok = true
	if not ok or not v in launch_vels(u):
		return false
	var pi: int = opt["pod"]
	_use_src(u, pi)
	var m: Dictionary
	if opt["mis"] != "":
		m = units[opt["mis"]]
	else:
		u["pods"][pi]["ms"][opt["mt"]] = int(u["pods"][pi]["ms"][opt["mt"]]) - 1
		m = _new_missile(u, pi, opt["mt"])
	m["st"] = "on"
	m["hex"] = h
	m["dir"] = posmod(d, 12)
	m["v"] = v
	m["zig"] = 0
	m["rev"] = false
	log_msg("%s lancia un %s (%s) in %s." % [uname(u), D.MNAME_FULL[m["cls"]].to_lower(), m["label"], hcode(h)])
	_rec({"k": "launch", "a": u["id"], "id": m["id"]})
	_st(side, "launched")
	await _pace(0.5)
	await _intercepts_at(m)
	return true


## [9.9] un MIMS lancia quattro missili non guidati
func _mims(side: int, r: Dictionary) -> bool:
	var m: Dictionary = units.get(str(r.get("mims", "")), {})
	if m.is_empty() or m["side"] != side or m["st"] != "on" or m["cls"] != "m" or m.get("mims_used", false):
		return false
	var pl: Array = r.get("pl", [])
	if pl.size() != 4:
		return false
	var spots := launch_spots(m)
	var vels := launch_vels(m)
	for p in pl:
		var ok := false
		for sp in spots:
			if sp[0] == p[0] and int(p[1]) in sp[1]:
				ok = true
		if not ok or not int(p[2]) in vels:
			return false
	m["mims_used"] = true
	m["rev"] = true
	var made := []
	for p in pl:
		var host := {"side": side, "label": m["label"], "hex": m["hex"], "dir": m["dir"], "v": m["v"], "pods": [], "civ": m["civ"], "id": m["id"]}
		var mm := _new_missile(host, -1, "ug")
		mm["civ"] = m["civ"]
		mm["host"] = ""
		mm["st"] = "on"
		mm["hex"] = p[0]
		mm["dir"] = posmod(int(p[1]), 12)
		mm["v"] = int(p[2])
		made.append(mm)
	log_msg("Il MIMS %s si apre e lancia quattro missili non guidati!" % m["label"])
	_st(side, "launched", 4)
	_rec({"k": "launch", "a": m["id"], "id": made[0]["id"]})
	await _pace(0.5)
	for mm in made:
		if mm["st"] == "on":
			await _intercepts_at(mm)
	return true


# ================================================================ vittoria

func ship_lost(u: Dictionary) -> bool:
	return u["st"] == "dead"


func _check_victory() -> void:
	if over:
		return
	var s0 := []
	var s1 := []
	for id in order:
		var u: Dictionary = units[id]
		if u["kind"] == "ship":
			(s0 if u["side"] == 0 else s1).append(u)
	match scn:
		0:
			if s0[0]["st"] == "dead":
				_win(1, "l'astronave dei tagliagole è distrutta.")
			elif s1[0]["st"] == "dead":
				_win(0, "l'astronave della guardia è distrutta.")
		1:
			if s0[0]["st"] == "dead":
				_win(1, "lo Sword di Venable è distrutto.")
			elif s1[0]["st"] == "dead" and s1[1]["st"] == "dead":
				_win(0, "entrambi i Dagger di Laidley sono distrutti.")
		2:
			var iota: Dictionary = s0[0]
			var gj := 0
			var dead := 0
			for u in s0:
				if u["st"] == "dead":
					dead += 1
				if u["cls"] == "Gamma" and u["st"] == "jumped":
					gj += 1
			if iota["st"] == "jumped":
				_win(0, "il Corco Iota è sfuggito nell'iperspazio.")
			elif gj >= 2:
				_win(0, "due Corco Gamma sono sfuggiti nell'iperspazio.")
			elif s1[0]["st"] == "dead":
				_win(0, "lo Sword federale è distrutto.")
			elif dead >= 3 and iota["st"] == "dead":
				_win(1, "tre navi dei contrabbandieri, Iota compreso, sono distrutte.")
			else:
				var left := 0
				for u in s0:
					if u["st"] == "on":
						left += 1
				if left == 0:
					_win(-1, "nessuna nave dei contrabbandieri resta in gioco, ma la condizione di vittoria non è stata raggiunta.")
		3:
			var mu: Dictionary = s0[0]
			if rdv_done:
				_win(1, "un Flute si è agganciato al Corco Mu: i pirati arrembano la nave!")
			elif mu["st"] == "dead":
				_win(-1, "il Corco Mu è distrutto.")
			elif mu["st"] == "on" and is_planet(mu["hex"]) and int(mu["v"]) == 1:
				_win(0, "il Corco Mu è in orbita attorno a Esata.")
			elif s1[0]["st"] == "dead" and s1[1]["st"] == "dead":
				_win(0, "entrambi i Flute pirati sono distrutti.")
		4:
			for u in s0:
				if u["st"] == "on" and is_planet(u["hex"]) and int(u["v"]) == 1:
					var cargo := 0
					for i in u["pods"].size():
						if D.PODS[u["pods"][i]["t"]].get("cargo", false) and pod_state(u, i) < 3:
							cargo += 1
					u["st"] = "orbit"
					for c in _children(u):
						c["st"] = "orbit"
					vp[0] += 1 + cargo
					log_msg("%s entra in orbita attorno a Zaraznov: %d punti al convoglio." % [uname(u), 1 + cargo])
			var p2 := 0
			for u in s0:
				var cargo_dead := 0
				var ncargo := 0
				for i in u["pods"].size():
					if D.PODS[u["pods"][i]["t"]].get("cargo", false):
						ncargo += 1
						if pod_state(u, i) == 3:
							cargo_dead += 1
				if u["st"] == "dead":
					p2 += 1 + ncargo
				else:
					p2 += cargo_dead
			for u in s1:
				if u["cls"] == "Flute" and u["st"] == "dead":
					p2 -= 2
			vp[1] = p2
			if s1[0]["st"] == "dead":
				_win(0, "il Clarinet degli insorti è distrutto.")
			elif vp[0] >= 8:
				_win(0, "il convoglio ha raggiunto 8 punti.")
			elif vp[1] >= 8:
				_win(1, "gli insorti hanno raggiunto 8 punti.")
			else:
				var left := 0
				for u in s0:
					if u["st"] == "on":
						left += 1
				if left == 0:
					var w := -1
					if vp[0] != vp[1]:
						w = 0 if vp[0] > vp[1] else 1
					_win(w, "nessuna nave del convoglio resta in gioco (punti %d a %d)." % [vp[0], vp[1]])


func _end_turn_checks() -> void:
	_check_victory()
	if over:
		return
	if scn == 1:
		var far := true
		for a in live_units(0):
			if a["kind"] == "mis":
				continue
			for b in live_units(1):
				if b["kind"] == "mis":
					continue
				if Hex.dist(a["hex"], b["hex"]) <= 25:
					far = false
		if far:
			_win(-1, "tutte le unità avversarie sono a più di 25 esagoni di distanza.")
			return
	if turn >= max_turns:
		var w := -1
		if scn == 4 and vp[0] != vp[1]:
			w = 0 if vp[0] > vp[1] else 1
		_win(w, "raggiunto il limite di %d turni." % max_turns)
