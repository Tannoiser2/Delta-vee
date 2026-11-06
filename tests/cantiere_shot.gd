extends SceneTree
## Foto del cantiere navale, della modifica di una nave, del menu con la battaglia libera e di una partita.
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/cantiere_shot.gd -- [cartella]

const D = preload("res://scripts/data/dv_data.gd")


func _init() -> void:
	_run()


func _snap(out: String, name: String) -> void:
	for k in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("foto ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/cantiere"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(0.5).timeout
	main.show_shipyard()
	await create_timer(0.8).timeout
	await _snap(out, "cantiere")
	var yd = main.current
	yd._add(0, "Mu")
	yd._edit(0, 0)
	await create_timer(0.5).timeout
	await _snap(out, "modifica_sword")
	yd._edit(0, 2)
	await create_timer(0.5).timeout
	await _snap(out, "modifica_mu")
	yd.edit_box.queue_free()
	yd.edit_box = null
	yd._random(1)
	await create_timer(0.3).timeout
	await _snap(out, "cantiere_casuale")
	yd._done()
	await create_timer(0.8).timeout
	await _snap(out, "menu_libera")
	main.current.modes = [2, 2]
	main.current.speed = 3
	main.current._on_start()
	await create_timer(6.0).timeout
	await _snap(out, "partita_libera")
	main.current.engine.abort = true
	main.current.engine.provide_decision(null)
	main.delete_save()
	print("fatto")
	quit()
