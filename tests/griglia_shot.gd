extends SceneTree
## Foto della mappa 2D e 3D con la griglia a opacità 1, 0,4 e 0 (restano i puntini).
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/griglia_shot.gd -- [cartella]

func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/griglia"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(0.5).timeout
	main.start_game({"scenario": 1, "seats": [{"name": "", "ai": false, "level": 1}, {"name": "", "ai": false, "level": 1}],
		"ai_delay": 0.0, "anim": 0.0, "view3d": false, "max_turns": 30, "tutorial": true})
	var g = main.current
	await create_timer(2.0).timeout
	g.tutor._collapse(true)
	for v3 in [false, true]:
		g.view3d = v3
		g._apply_view()
		await create_timer(1.0).timeout
		for a in [1.0, 0.4, 0.0]:
			g.board2d.set_grid_alpha(a)
			g.board3d.set_grid_alpha(a)
			for k in 4:
				await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [out, "3d" if v3 else "2d", int(a * 10)])
	print("fatto")
	quit()
