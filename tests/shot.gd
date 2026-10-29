extends SceneTree
## Fotografie dell'interfaccia (serve un display, anche virtuale: xvfb-run).
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --path . -s tests/shot.gd -- <cartella> [scenario] [3d]

var out := "/tmp/shots"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var scn := int(args[1]) if args.size() > 1 else 1
	var v3 := args.size() > 2 and args[2] == "3d"
	DirAccess.make_dir_recursive_absolute(out)
	_run(scn, v3)


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _run(scn: int, v3: bool) -> void:
	root.size = Vector2i(1920, 1080)
	var main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(1.0).timeout
	await _snap("menu")
	main.start_game({"scenario": scn - 1, "seats": [{"name": "", "ai": false, "level": 1}, {"name": "", "ai": true, "level": 1}],
		"ai_delay": 0.0, "anim": 4.0, "view3d": v3, "max_turns": 30, "seed": 5})
	var g = main.current
	await create_timer(2.0).timeout
	await _snap("p1_%d" % scn)
	# il Giocatore 1 lascia fare all'IA (pulsante Suggerisci) per qualche fase
	for k in 14:
		var req: Dictionary = g.pending
		if req.is_empty():
			await create_timer(0.8).timeout
			continue
		if req["type"] == "cmd" and k == 2:
			await _snap("cmd_%d" % scn)
		if req["type"] == "fire":
			# seleziona un'arma per vedere i bersagli
			var s = g.engine.ais[0].decide(g.engine, 0, req)
			if s is Dictionary and s.has("w"):
				g.sel = s["s"]
				g.aux = {"src": s["src"], "w": s["w"], "t": s["t"]}
				g._rebuild()
				g._card()
				await _snap("fire_%d_%d" % [scn, k])
		var r = g.engine.ais[0].decide(g.engine, 0, req)
		g._submit(r)
		await create_timer(1.2).timeout
	await _snap("late_%d" % scn)
	g.view3d = not g.view3d
	g._apply_view()
	g.board3d.fit()
	await create_timer(1.0).timeout
	await _snap("other_%d" % scn)
	if g.view3d:
		var u = g.engine.live_units(0, "ship")[0]
		g.board3d.center_on(Hex.center(u["hex"], 1.0))
		g.board3d.dist = 9.0
		g.board3d.pitch = 0.6
		g.board3d._update_cam()
		await create_timer(0.5).timeout
		await _snap("close_%d" % scn)
	# fine partita e replay
	g.engine.abort = true
	g.engine.provide_decision(null)
	await create_timer(0.5).timeout
	g.ended = true
	g.start_replay()
	g.rp_time = g.rp_starts[-1] * 0.6
	await create_timer(0.6).timeout
	await _snap("replay_%d" % scn)
	quit()
