extends SceneTree
## Galleria dei modelli 3D: le navi in ordine di stazza per i due lati, con i getti dei motori.
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/galleria3d_shot.gd -- [cartella] [velocità]

const D = preload("res://scripts/data/dv_data.gd")
const ORDER := [["ship", "TX"], ["ship", "Piccolo"], ["ship", "Dagger"], ["ship", "Gamma"], ["ship", "Flute"], ["ship", "Sword"],
	["ship", "Zeta"], ["ship", "Clarinet"], ["ship", "Spear"], ["ship", "Iota"], ["ship", "Mu"], ["bc", "A"], ["mis", "g"]]


func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/galleria3d"
	var v := int(args[1]) if args.size() > 1 else 5
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var b = load("res://scripts/ui/board_3d.gd").new()
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.09)
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.glow_enabled = true
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.3
	w.add_child(sun)
	var x := 0.0
	for i in ORDER.size():
		var kind: String = ORDER[i][0]
		var cls: String = ORDER[i][1]
		var ln: float = b.model_len(kind, cls)
		x += ln * 0.5 + 0.35
		for side in 2:
			var m: Node3D = b._model(kind, cls, side)
			m.position = Vector3(x, 0, side * 1.3)
			w.add_child(m)
			b._set_flames(m, kind, cls, v, true)
		x += ln * 0.5
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(x * 0.5, 4.2, 6.2)
	cam.look_at(Vector3(x * 0.5, 0, 0.6))
	cam.fov = 70
	for k in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/galleria_v%d.png" % v)
	cam.position = Vector3(2.2, 1.4, 3.0)
	cam.look_at(Vector3(2.2, 0, 0.6))
	cam.fov = 45
	for k in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/vicino_v%d.png" % v)
	cam.position = Vector3(x - 3.2, 1.6, 3.6)
	cam.look_at(Vector3(x - 2.2, 0, 0.6))
	for k in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/grandi_v%d.png" % v)
	quit()
