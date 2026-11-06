extends SceneTree
## Fotografie degli effetti (serve un display): un colpo di ogni tipo e un'esplosione, in 2D e in 3D.

func _init() -> void:
	_run()

func _snap(n: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/fx_%s.png" % n)
	print("foto ", n)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.add_child(UI.Starfield.new())
	var e := DVEngine.new()
	e.headless = true
	root.add_child(e)
	e.setup({"scenario": 0, "seats": [{"name": "", "ai": true, "level": 1}, {"name": "", "ai": true, "level": 1}]})
	e.units["0sE"]["hex"] = Vector2i(3, 6)
	e.units["1sD"]["hex"] = Vector2i(9, 4)
	for mode in ["2d", "3d"]:
		var b
		if mode == "2d":
			b = load("res://scripts/ui/board_2d.gd").new()
		else:
			b = load("res://scripts/ui/board_3d.gd").new()
		b.size = Vector2(1600, 900)
		root.add_child(b)
		await process_frame
		b.set_engine(e)
		var base := Timeline.from_snapshot(e.snapshot(), e.reg, e.maps)
		b.set_state(base)
		await process_frame
		if mode == "2d":
			b.zoom = 1.6
			b.world.scale = Vector2(1.6, 1.6)
			b.center_on(Vector2(9, 8))
		else:
			b.center_on(Vector2(9, 8))
			b.dist = 11.0
			b.pitch = 0.9
			b._update_cam()
		var a := Hex.center(Vector2i(3, 6), 1.0)
		var c := Hex.center(Vector2i(9, 4), 1.0)
		for w in ["lb", "lbb", "pb", "pbb"]:
			for t in [0.18, 0.62]:
				var st := base.duplicate()
				st["fx"] = [{"k": "beam", "a": a, "b": c, "w": w, "hit": true, "t": t}]
				b.set_state(st)
				await create_timer(0.1).timeout
				await _snap("%s_%s_%d" % [mode, w, int(t * 100)])
		for t in [0.12, 0.35, 0.7]:
			var st := base.duplicate()
			st["fx"] = [{"k": "boom", "p": c, "t": t}]
			b.set_state(st)
			await create_timer(0.1).timeout
			await _snap("%s_boom_%d" % [mode, int(t * 100)])
		b.queue_free()
		await process_frame
	quit()
