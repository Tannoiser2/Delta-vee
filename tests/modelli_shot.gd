extends SceneTree
## Foto dei modelli 3D importati (vista dall'alto e di lato) e misure, per controllarne l'orientamento.
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/modelli_shot.gd -- [cartella]

const NAMES := ["TX", "Piccolo", "Dagger", "Gamma", "Flute", "Sword", "Zeta", "Clarinet", "Spear", "Iota", "Mu", "missile"]


func _init() -> void:
	_run()


func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * n.transform
	if n is MeshInstance3D:
		var b: AABB = t * n.mesh.get_aabb()
		acc[0] = b if acc[0] == null else acc[0].merge(b)
	for c in n.get_children():
		_aabb(c, t, acc)


func _run() -> void:
	var out := "/tmp/modelli"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.12, 0.2)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	w.add_child(sun)
	for i in NAMES.size():
		var sc: PackedScene = load("res://assets/models/%s.glb" % NAMES[i])
		var m: Node3D = sc.instantiate()
		var acc := [null]
		_aabb(m, Transform3D.IDENTITY, acc)
		var b: AABB = acc[0]
		var s := 1.0 / maxf(b.size.x, maxf(b.size.y, b.size.z))
		m.scale = Vector3.ONE * s
		m.position = Vector3((i % 4) * 1.4, 0, (i / 4) * 1.4) - b.get_center() * s
		w.add_child(m)
		var l := Label3D.new()
		l.text = NAMES[i]
		l.font_size = 48
		l.pixel_size = 0.004
		l.position = Vector3((i % 4) * 1.4, 0.7, (i / 4) * 1.4 + 0.55)
		# punto rosso a +x, blu a +z
		for ax in [[Vector3(0.7, 0, 0), Color.RED], [Vector3(0, 0, 0.7), Color.BLUE]]:
			var d := MeshInstance3D.new()
			d.mesh = SphereMesh.new()
			d.scale = Vector3.ONE * 0.12
			var mm := StandardMaterial3D.new()
			mm.albedo_color = ax[1]
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			d.material_override = mm
			d.position = Vector3((i % 4) * 1.4, 0.3, (i / 4) * 1.4) + ax[0]
			w.add_child(d)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		w.add_child(l)
		print("%s aabb pos %s size %s" % [NAMES[i], b.position, b.size])
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(2.1, 6, 1.4)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.fov = 50
	await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/alto.png")
	cam.position = Vector3(2.1, 1.5, 6.5)
	cam.look_at(Vector3(2.1, 0, 1.4))
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/lato.png")
	quit()
