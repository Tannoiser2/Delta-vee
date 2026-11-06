extends SceneTree
## Battaglie libere IA contro IA con flotte del cantiere (proposta e casuali): controlla che finiscano,
## i punti e la ripresa da salvataggio.
## Uso: godot --headless --path . -s tests/libera_sim.gd -- [partite] [livello]

const D = preload("res://scripts/data/dv_data.gd")


func _init() -> void:
	_run()


func _fleet(rng: RandomNumberGenerator, cap: int) -> Array:
	var classes := ["Piccolo", "Dagger", "Gamma", "Flute", "Sword", "Zeta", "Clarinet", "Spear", "Iota", "Mu", "TX", "T5000"]
	var fl := []
	for k in 40:
		if fl.size() >= D.YARD_MAX:
			break
		var cls: String = classes[rng.randi_range(0, classes.size() - 1)]
		var pods := []
		for j in int(D.SHIPS[cls]["pods"]):
			var t: String = D.YARD_PODS[rng.randi_range(0, D.YARD_PODS.size() - 1)]
			var pd := [t, rng.randi_range(0, 2)]
			if t == "bcpod":
				pd.append("TX")
			if t == "tractor":
				pd.append(8)
			pods.append(pd)
		var s := {"cls": cls, "pods": pods}
		if D.fleet_pts(fl) + D.ship_pts(s) <= cap:
			fl.append(s)
	return fl


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 6
	var lvl := int(args[1]) if args.size() > 1 else 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var res := {}
	var turns := 0
	var bad := 0
	for g in n:
		var y := D.yard_default()
		if g > 0:
			y["fleets"] = [_fleet(rng, 200), _fleet(rng, 200)]
			y["terrain"] = g % 3
			y["dist"] = g % 3
		var cfg := {"scenario": D.CUSTOM, "custom": D.custom_scenario(y), "seed": 100 + g, "max_turns": 30,
			"seats": [{"name": "", "ai": true, "level": lvl}, {"name": "", "ai": true, "level": lvl}]}
		var e := DVEngine.new()
		e.headless = true
		root.add_child(e)
		e.setup(cfg)
		e.ais[0] = DVAI.new(lvl, g * 2 + 1)
		e.ais[1] = DVAI.new(lvl, g * 2 + 2)
		await e.run()
		var w := int(e.result.get("winner", -9))
		res[w] = res.get(w, 0) + 1
		turns += e.turn
		# ripresa: stesse decisioni in una configurazione passata da JSON (come dal salvataggio)
		var c2: Dictionary = JSON.parse_string(JSON.stringify(cfg))
		c2["scenario"] = int(c2["scenario"])
		c2["seed"] = int(c2["seed"])
		c2["dec"] = e.dec_log.duplicate()
		var b := DVEngine.new()
		b.headless = true
		root.add_child(b)
		b.setup(c2)
		b.ais[0] = DVAI.new(lvl, 9)
		b.ais[1] = DVAI.new(lvl, 9)
		await b.run()
		var same := b.log_lines == e.log_lines
		if not same:
			bad += 1
		print("  partita %d: punti %d contro %d, vince %d al turno %d (%s) — ripresa identica %s" % [g, D.fleet_pts(y["fleets"][0]), D.fleet_pts(y["fleets"][1]), w, e.turn, e.result.get("reason", ""), same])
		e.queue_free()
		b.queue_free()
	print("Battaglia libera: vittorie %s, turni medi %.1f, riprese diverse %d" % [res, float(turns) / n, bad])
	quit()
