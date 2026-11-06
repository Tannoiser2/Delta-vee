extends SceneTree
## Fotografie e controlli di tutorial, partita salvata e statistiche di fine partita.
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/novita_shot.gd -- [cartella]

var out := "/tmp/novita"
var main


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _wait_pending(g, sec := 20.0) -> bool:
	var t := 0.0
	while g.pending.is_empty() and not g.ended and t < sec:
		await create_timer(0.2).timeout
		t += 0.2
	return not g.pending.is_empty()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	main.delete_save()
	await create_timer(0.5).timeout

	# ---- tutorial
	main.current._on_tutorial()
	var g = main.current
	await create_timer(1.5).timeout
	await _snap("tut_1_benvenuto")
	g.tutor._next()
	g.tutor._next()
	await _snap("tut_2_newton")
	g.tutor._next()
	var shots := 0
	for k in 16:
		if not await _wait_pending(g):
			break
		await create_timer(0.4).timeout
		var tp: String = g.pending["type"]
		if not g.tutor.step.is_empty():
			# si scorrono i passi fino a quello che chiede di agire, fotografandone uno con i pulsanti evidenziati
			var guard := 0
			while not g.tutor.step.is_empty() and g.tutor.step.get("until", "next") == "next" and guard < 8:
				if g.tutor.step.has("hl") and shots < 6:
					await create_timer(0.3).timeout
					await _snap("tut_%d_%s" % [3 + shots, tp])
					shots += 1
				g.tutor._next()
				guard += 1
			if not g.tutor.step.is_empty() and shots < 6:
				await create_timer(0.3).timeout
				await _snap("tut_%d_%s" % [3 + shots, tp])
				shots += 1
		var r = g.engine.ais[0].decide(g.engine, 0, g.pending)
		g._submit(r)
		await create_timer(0.3).timeout
	print("tutorial: passi mostrati %d, capitoli %s" % [g.tutor.done_steps, g.tutor.seen.keys()])
	print("tutorial salvato? %s (deve essere false)" % (not main.saved_game().is_empty()))

	# ---- partita salvata e ripresa
	main.show_menu()
	await create_timer(0.3).timeout
	main.start_game({"scenario": 1, "seats": [{"name": "Stefano", "ai": false, "level": 1}, {"name": "", "ai": true, "level": 2}],
		"ai_delay": 0.0, "anim": 3.0, "view3d": false, "max_turns": 30})
	g = main.current
	for k in 9:
		if not await _wait_pending(g):
			break
		g._submit(g.engine.ais[0].decide(g.engine, 0, g.pending))
		await create_timer(0.3).timeout
	await _wait_pending(g)
	var lines: Array = g.engine.log_lines.duplicate()
	var fp: String = g.engine.fingerprint()
	var turn: int = g.engine.turn
	g.engine.abort = true
	g.engine.provide_decision(null)
	main.show_menu()
	await create_timer(0.8).timeout
	await _snap("menu_partita_salvata")
	main.resume_game()
	g = main.current
	await create_timer(2.0).timeout
	await _wait_pending(g)
	var same: bool = g.engine.log_lines == lines and g.engine.fingerprint() == fp
	print("ripresa: turno %d (era %d), diario identico %s" % [g.engine.turn, turn, same])
	await _snap("partita_ripresa")
	g.engine.abort = true
	g.engine.provide_decision(null)
	main.delete_save()

	# ---- statistiche di fine partita (IA contro IA)
	main.show_menu()
	await create_timer(0.3).timeout
	main.start_game({"scenario": 1, "seats": [{"name": "", "ai": true, "level": 2}, {"name": "", "ai": true, "level": 2}],
		"ai_delay": 0.0, "anim": 0.0, "view3d": false, "max_turns": 20, "seed": 77})
	g = main.current
	var t := 0.0
	while not g.ended and t < 240.0:
		await create_timer(0.5).timeout
		t += 0.5
	await create_timer(0.8).timeout
	await _snap("fine_statistiche")
	print("statistiche: %s" % [g.engine.stats])
	print("salvataggio dopo la fine? %s (deve essere false)" % (not main.saved_game().is_empty()))
	quit()
