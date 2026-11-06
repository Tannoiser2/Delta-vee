extends SceneTree
## Foto delle astronavi 3D sul tabellone (modelli Meshy, colori dei due lati, getti dei motori).
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/navi3d_shot.gd -- [cartella]

var out := "/tmp/navi3d"
var main


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func _snap(name: String) -> void:
	for k in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _game(scn: int) -> Object:
	main.show_menu()
	await create_timer(0.3).timeout
	main.start_game({"scenario": scn, "seats": [{"name": "", "ai": false, "level": 1}, {"name": "", "ai": false, "level": 1}],
		"ai_delay": 0.0, "anim": 0.0, "view3d": true, "max_turns": 30, "seed": 3})
	var g = main.current
	await create_timer(4.0).timeout
	return g


func _look(g, id: String, d: float, yaw: float, pitch: float) -> void:
	var b = g.board3d
	var u: Dictionary = g.engine.units[id]
	var p: Vector2 = Hex.center(u["hex"], 1.0)
	b.target = Vector3(p.x, 0.5, p.y)
	b.dist = d
	b.yaw = yaw
	b.pitch = pitch
	b._update_cam()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(0.5).timeout
	for scn in [4, 3, 1, 2]:
		var g = await _game(scn)
		var shown := 0
		for id in g.engine.units:
			var u: Dictionary = g.engine.units[id]
			if u["st"] != "on" or shown >= 3:
				continue
			_look(g, id, 4.5, 0.6 + shown * 1.7, 0.45)
			await _snap("s%d_%s" % [scn + 1, id])
			shown += 1
		g.board3d.fit()
		await _snap("s%d_insieme" % [scn + 1])
		g.engine.abort = true
		g.engine.provide_decision(null)
		main.delete_save()
	quit()
