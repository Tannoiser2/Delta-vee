extends SceneTree
## Foto del pannello di destra a schede (Ordini, Caratteristiche, Moduli) in vari scenari e fasi,
## e controllo che nessuna scheda debba scorrere.
## Uso: xvfb-run -a godot --rendering-driver opengl3 --path . -s tests/pannello_shot.gd -- [cartella]

var out := "/tmp/pannello"
var main
var overflow := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	var g = main.current
	for k in g.tab_scroll:
		var sc: ScrollContainer = g.tab_scroll[k]
		if sc.visible and sc.get_v_scroll_bar().visible:
			print("  SCORRE: %s scheda %s" % [name, k])
			overflow += 1
	print("foto ", name)


func _wait_pending(g, sec := 30.0) -> bool:
	var t := 0.0
	while g.pending.is_empty() and t < sec:
		await create_timer(0.2).timeout
		t += 0.2
	return not g.pending.is_empty()


func _game(scn: int) -> Object:
	main.show_menu()
	await create_timer(0.3).timeout
	main.start_game({"scenario": scn, "seats": [{"name": "", "ai": false, "level": 1}, {"name": "", "ai": false, "level": 1}],
		"ai_delay": 0.0, "anim": 0.0, "view3d": false, "max_turns": 30, "tutorial": true})
	var g = main.current
	await _wait_pending(g)
	await create_timer(0.5).timeout
	return g


## passa le decisioni (con l'IA) finché non arriva una del tipo voluto per il lato voluto
func _until(g, typ: String, side: int, n := 40) -> bool:
	for k in n:
		if not await _wait_pending(g):
			return false
		if g.pending["type"] == typ and int(g.pending["seat"]) == side:
			return true
		var sd := int(g.pending["seat"])
		g._submit(g.engine.ais[sd].decide(g.engine, sd, g.pending))
		await create_timer(0.2).timeout
	return false


func _tabs(g, id: String, name: String) -> void:
	g.select(id)
	g._show_tab("ord")
	await _snap(name + "_ordini")
	g._show_tab("car")
	await _snap(name + "_caratteristiche")
	if not g.tab_btns["mod"].disabled:
		g._show_tab("mod")
		await _snap(name + "_moduli")
		g.pod_detail = 0
		g._card()
		await _snap(name + "_modulo1")
		g.pod_detail = -1
		g._card()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	main = load("res://scripts/ui/main.gd").new()
	root.add_child(main)
	await create_timer(0.5).timeout
	DVAI.new(1, 1)
	# scenario 5: convoglio (Clarinet con 7 moduli, Corco Zeta con 6)
	var g = await _game(4)
	g.engine.ais[0] = DVAI.new(1, 3)
	g.engine.ais[1] = DVAI.new(1, 4)
	if await _until(g, "cmd", 1):
		var ids: Array = []
		for u in g.engine.live_units(1, "ship"):
			ids.append(u["id"])
		await _tabs(g, ids[0], "s5_comando")
	if await _until(g, "fire", 0):
		var u0: Dictionary = g.engine.live_units(0, "ship")[0]
		await _tabs(g, u0["id"], "s5_fuoco")
	# scenario 4: il Corco Mu con 12 moduli
	g.engine.abort = true
	g.engine.provide_decision(null)
	g = await _game(3)
	g.engine.ais[0] = DVAI.new(1, 5)
	g.engine.ais[1] = DVAI.new(1, 6)
	if await _until(g, "cmd", 0) or true:
		for u in g.engine.live_units(0, "ship"):
			if u["cls"] == "Mu":
				await _tabs(g, u["id"], "s4_mu")
	g.engine.abort = true
	g.engine.provide_decision(null)
	print("ESITO: %s" % ("nessuna scheda scorre" if overflow == 0 else "%d schede scorrono" % overflow))
	quit()
