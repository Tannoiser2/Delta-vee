extends SceneTree
## Fotografie del replay continuo (serve un display): xvfb-run godot --path . -s tests/replay_shot.gd -- [scenario] [3d]

func _init() -> void:
	_run()

func _snap(n: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/rp_%s.png" % n)
	print("foto ", n)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scn := int(args[0]) if args.size() > 0 else 2
	root.size = Vector2i(1920, 1080)
	var main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(0.3).timeout
	main.start_game({"scenario": scn - 1, "seats": [{"name": "", "ai": true, "level": 1}, {"name": "", "ai": true, "level": 1}],
		"ai_delay": 0.0, "anim": 60.0, "view3d": args.size() > 1 and args[1] == "3d", "max_turns": 8, "seed": 21})
	var g = main.current
	var guard := 0
	while not g.ended and guard < 6000:
		guard += 1
		await process_frame
	print("finita al turno ", g.engine.turn, " segmenti ", g.engine.history.size())
	if is_instance_valid(g.end_panel):
		g.end_panel.queue_free()
	g.start_replay()
	g.rp_play = false
	var tot: float = g.rp_track.total
	print("durata replay ", tot)
	# cerca istanti con colpi in volo e con esplosioni
	var shots := 0
	for i in 2400:
		var t := tot * i / 2400.0
		var st: Dictionary = g.rp_track.state_at(t)
		for f in st["fx"]:
			if f["k"] == "beam" and f["t"] > 0.15 and f["t"] < 0.4 and shots < 4 and i % 7 == 0:
				g.rp_time = t
				await process_frame
				await _snap("shot_%d_%s" % [shots, f["w"]])
				shots += 1
				break
	g.rp_time = tot * 0.35
	await process_frame
	await _snap("mid")
	quit()
