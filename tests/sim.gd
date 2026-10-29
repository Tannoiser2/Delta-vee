extends SceneTree
## Partite simulate fra IA, senza grafica: controlla che le regole reggano e misura esiti e durata.
## Uso: godot --headless --path . -s tests/sim.gd -- [scenario 1-5 o 0 = tutti] [partite] [livello]
## DV_LOG=1 stampa la fine del diario della prima partita; DV_LIVE=1 tutto il diario.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := int(args[0]) if args.size() > 0 else 0
	var games := int(args[1]) if args.size() > 1 else 4
	var lv := int(args[2]) if args.size() > 2 else 1
	_run(only, games, lv)


func _run(only: int, games: int, lv: int) -> void:
	await process_frame
	for scn in 5:
		if only > 0 and scn != only - 1:
			continue
		var wins := {}
		var turns := 0
		var t0 := Time.get_ticks_msec()
		var reasons := {}
		for g in games:
			var eng := DVEngine.new()
			eng.headless = true
			root.add_child(eng)
			eng.setup({"scenario": scn, "seats": [{"name": "", "ai": true, "level": lv}, {"name": "", "ai": true, "level": lv}],
				"seed": 1000 + g, "max_turns": 40})
			eng.ais[0] = DVAI.new(lv, 50 + g * 7)
			eng.ais[1] = DVAI.new(lv, 51 + g * 7)
			if OS.get_environment("DV_LIVE") == "1":
				eng.log_added.connect(func(t): print(t))
			await eng.run()
			if OS.get_environment("DV_LOG") == "1" and g == 0:
				for l in eng.log_lines.slice(-40):
					print("  ", l)
			var w: int = eng.result.get("winner", -9)
			wins[w] = wins.get(w, 0) + 1
			var rs: String = str(eng.result.get("reason", "?"))
			reasons[rs] = reasons.get(rs, 0) + 1
			turns += eng.turn
			var fires := 0
			var launches := 0
			for h in eng.history:
				if h["k"] == "fire":
					fires += 1
				if h["k"] == "launch":
					launches += 1
			print("  partita %d: vince %d al turno %d (%s) — fuochi %d, lanci %d, segmenti %d" % [g, w, eng.turn, rs, fires, launches, eng.history.size()])
			eng.queue_free()
		print("Scenario %d: vittorie %s, turni medi %.1f, %d ms" % [scn + 1, wins, float(turns) / games, Time.get_ticks_msec() - t0])
	quit()
