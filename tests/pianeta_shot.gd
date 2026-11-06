extends SceneTree
## Foto del pianeta che gira con le lune (2D e 3D) e del replay continuo con le scie.
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/pianeta_shot.gd -- [cartella]


func _init() -> void:
	_run()


func _snap(out: String, name: String) -> void:
	for k in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/pianeta"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(0.5).timeout
	# pianeti degli scenari 4 (Esata) e 5 (Zaraznov)
	for scn in [3, 4]:
		main.start_game({"scenario": scn, "seats": [{"name": "", "ai": false, "level": 1}, {"name": "", "ai": false, "level": 1}],
			"ai_delay": 0.0, "anim": 0.0, "view3d": false, "max_turns": 30, "tutorial": true})
		var g = main.current
		await create_timer(1.5).timeout
		g.tutor._collapse(true)
		var c: Vector2 = Hex.center(g.engine.planets[0], 1.0)
		g.board2d.zoom = 1.6
		g.board2d.world.scale = Vector2(1.6, 1.6)
		g.board2d.center_on(c)
		await create_timer(0.5).timeout
		await _snap(out, "s%d_2d_a" % (scn + 1))
		await create_timer(2.0).timeout
		await _snap(out, "s%d_2d_b" % (scn + 1))
		g.view3d = true
		g._apply_view()
		await create_timer(0.8).timeout
		g.board3d.target = Vector3(c.x, 1.0, c.y)
		g.board3d.dist = 11.0
		g.board3d.pitch = 0.5
		g.board3d._update_cam()
		await create_timer(0.5).timeout
		await _snap(out, "s%d_3d" % (scn + 1))
		g.engine.abort = true
		g.engine.provide_decision(null)
		main.show_menu()
		await create_timer(0.3).timeout
	# replay con le scie
	main.start_game({"scenario": 1, "seats": [{"name": "", "ai": true, "level": 1}, {"name": "", "ai": true, "level": 1}],
		"ai_delay": 0.0, "anim": 0.0, "view3d": false, "max_turns": 12, "seed": 5})
	var g2 = main.current
	var t := 0.0
	while not g2.ended and t < 120.0:
		await create_timer(0.5).timeout
		t += 0.5
	if g2.end_panel != null:
		g2.end_panel.queue_free()
	main.delete_save()
	g2.start_replay()
	# moto continuo: una nave in movimento non si ferma al passaggio fra due turni
	var tr: ReplayTrack = g2.rp_track
	var stops := 0
	var checks := 0
	for id in tr.keys:
		if not id.contains("s"):
			continue
		for turn in range(2, 10):
			var tb := ReplayTrack.START + (turn - 1) * ReplayTrack.TT
			var a := tr.pos_at(id, tb - 0.15)
			var b := tr.pos_at(id, tb)
			var c := tr.pos_at(id, tb + 0.15)
			if a.distance_to(b) > 0.001 and b.distance_to(c) > 0.001:
				checks += 1
			elif a.distance_to(c) > 0.001:
				stops += 1
	print("moto continuo: %d passaggi fluidi, %d con una sosta" % [checks, stops])
	g2.rp_time = 9.0
	await create_timer(2.5).timeout
	await _snap(out, "replay_2d")
	g2.rp_follow = false
	g2.board2d.zoom = 1.4
	g2.board2d.world.scale = Vector2(1.4, 1.4)
	var uid: String = g2.engine.order[0]
	g2.rp_time = 14.0
	await create_timer(0.3).timeout
	g2.board2d.center_on(tr.pos_at(uid, g2.rp_time))
	await create_timer(1.5).timeout
	await _snap(out, "replay_2d_scie")
	g2.view3d = true
	g2._apply_view()
	await create_timer(2.5).timeout
	await _snap(out, "replay_3d")
	print("fatto")
	quit()
