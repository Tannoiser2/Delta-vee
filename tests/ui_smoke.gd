extends SceneTree
## Prova a vuoto dell'interfaccia: per ogni scenario una persona (guidata dall'IA) apre tutti i pannelli
## di comando e di fuoco per ogni unità, con le varie modalità, prima di confermare.
## Uso: godot --headless --path . -s tests/ui_smoke.gd -- [scenario 1-5 o 0] [decisioni]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := int(args[0]) if args.size() > 0 else 0
	var steps := int(args[1]) if args.size() > 1 else 60
	_run(only, steps)


func _run(only: int, steps: int) -> void:
	var main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await process_frame
	for scn in 5:
		if only > 0 and scn != only - 1:
			continue
		for human in [0, 1]:
			var seats := [{"name": "", "ai": human != 0, "level": 1}, {"name": "", "ai": human != 1, "level": 1}]
			main.start_game({"scenario": scn, "seats": seats, "ai_delay": 0.0, "anim": 50.0, "view3d": human == 1, "max_turns": 6, "seed": 11 + scn})
			var g = main.current
			var n := 0
			var guard := 0
			while n < steps and guard < 4000:
				guard += 1
				await process_frame
				if g.ended:
					break
				var req: Dictionary = g.pending
				if req.is_empty():
					continue
				n += 1
				var e: DVEngine = g.engine
				var side := int(req["seat"])
				match str(req["type"]):
					"cmd":
						for u in g._own_units(side):
							g.select(u["id"])
							for md in ["weave", "launchbc", "tractor"]:
								g.mode = md
								g.aux = {"pod": 0, "a": 0, "tt": 0, "v": 1, "dir": u["dir"]}
								if md == "launchbc":
									g.aux["hex"] = Hex.neighbors(u["hex"])[0]
								g._build_decision()
								g._set_state(Timeline.from_snapshot(e.snapshot(), e.reg, e.maps))
							g.mode = ""
							g.aux = {}
							g._build_decision()
					"fire":
						for u in g._fire_units(side):
							g.select(u["id"])
							if e.fire_budget.has(u["id"]):
								for src in e.fire_sources(u):
									for w in e.weapons_of(u, src):
										var tg = e.valid_targets(side)
										g.aux = {"src": src, "w": w, "t": tg[0]["id"] if not tg.is_empty() else ""}
										g._build_decision()
								for lo in e.launchable(u):
									g.mode = "launch"
									g.aux = {"pod": lo["pod"], "mt": lo["mt"], "v": 1, "hex": e.launch_spots(u)[0][0], "dir": e.launch_spots(u)[0][1][0]}
									g._build_decision()
									g._set_state(Timeline.from_snapshot(e.snapshot(), e.reg, e.maps))
							g.mode = ""
							g.aux = {}
					"deploy":
						for s in req["ships"]:
							g.aux = {"ship": s["id"]}
							g._build_decision()
							g._mode_click(s["allowed"][0])
				var r = e.ais[side].decide(e, side, req)
				g._submit(r)
			print("scenario %d, persona %d: %d decisioni, turno %d, fase %s" % [scn + 1, human + 1, n, g.engine.turn, g.engine.phase])
			g.engine.abort = true
			if not g.pending.is_empty():
				g.engine.provide_decision(null)
			main.show_menu()
			await process_frame
	quit()
