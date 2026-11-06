extends Control
## La partita: mappa 2D o 3D, la scheda dell'unità scelta (come lo Spaceship Log), i comandi della fase,
## il diario di bordo e, alla fine, il replay continuo di tutta la partita.

const D = preload("res://scripts/data/dv_data.gd")
const PANEL_W := 520.0
const TOP_H := 62.0

var main
var config := {}
var engine: DVEngine
var online: OnlineSession
var local_seats: Array = []
var board2d
var board3d
var view3d := false
var board_area: Control
var right: VBoxContainer
var head_box: VBoxContainer      # intestazione fissa dell'unità scelta
var act_box: VBoxContainer       # scheda Ordini
var car_box: VBoxContainer       # scheda Caratteristiche
var mod_box: VBoxContainer       # scheda Moduli
var foot_box: VBoxContainer      # pulsanti di fine fase, sempre visibili
var tab := "ord"
var tab_btns := {}
var tab_scroll := {}
var pod_detail := -1
var phase_lbl: Label
var status_lbl: Label
var log_lbl: RichTextLabel
var log_full: Control
var replay_bar: Control

var pending := {}
var plan := {}
var sel := ""
var mode := ""
var aux := {}
var _click_cycle := {}
var anim_idx := -1
var anim_t0 := 0.0
var live_dirty := true
var replaying := false
var rp_time := 0.0
var rp_speed := 1.0
var rp_play := true
var rp_starts: Array = []
var rp_slider: HSlider
var rp_lbl: Label
var rp_btn: Button
var _rp_drag := false
var rp_track: ReplayTrack
var _rp_last := 0.0
var rp_follow := true


## la telecamera del replay segue l'azione: i colpi in corso o, se non ce ne sono, tutte le unità
func _follow(st: Dictionary, dt: float) -> void:
	var pts: Array = []
	for f in st.get("fx", []):
		if f.has("a") and f.has("b"):
			pts.append(f["a"])
			pts.append(f["b"])
		elif f.has("p"):
			pts.append(f["p"])
	if pts.is_empty():
		for id in st.get("units", {}):
			pts.append(st["units"][id]["p"])
	if pts.is_empty():
		return
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var k := clampf(dt * 1.6, 0.0, 1.0)
	if view3d:
		board3d.target = board3d.target.lerp(Vector3(c.x, 0, c.y), k)
		board3d._update_cam()
	else:
		var want: Vector2 = board2d.size * 0.5 - c * board2d.S * board2d.zoom
		board2d.world.position = board2d.world.position.lerp(want, k)
var ended := false
var hover_lbl: Label
var _last_fire := {}
var tutor: Tutor


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine = DVEngine.new()
	add_child(engine)
	online = config.get("online", null)
	if online != null:
		add_child(online)
		online.view = self
		engine.online = online
	var saving: bool = online == null and not config.get("tutorial", false) and main != null
	if saving and not config.has("seed"):
		config["seed"] = randi()
	engine.setup(config)
	for s in 2:
		var p: Dictionary = engine.players[s]
		engine.ais[s] = DVAI.new(int(p["level"]), int(config.get("seed", 0)) * 7 + s + 1 if config.has("seed") else randi())
		if online != null:
			if s == online.seat:
				local_seats.append(s)
		elif not p["ai"]:
			local_seats.append(s)
	view3d = bool(config.get("view3d", false))
	_build()
	if engine.resuming:
		status_lbl.text = "Riprendo la partita salvata…"
	engine.changed.connect(_mark)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.game_ended.connect(_on_end)
	engine.fx.connect(_on_fx)
	if saving:
		engine.decided.connect(func(): main.save_game(config, engine))
	if engine.resuming:
		engine.resumed.connect(_on_resumed)
	board2d.set_engine(engine)
	board3d.set_engine(engine)
	if main != null:
		board2d.set_grid_alpha(main.grid_alpha)
		board3d.set_grid_alpha(main.grid_alpha)
	_apply_view()
	_refresh()
	_fit.call_deferred()
	if online != null and online.role != "host":
		online.heartbeat_loop()
	if config.get("tutorial", false):
		tutor = Tutor.new()
		tutor.g = self
		add_child(tutor)
		tutor.event("start")
	engine.run.call_deferred()


func _fit() -> void:
	await get_tree().process_frame
	board2d.fit()
	board3d.fit()


## lati di cui si vedono le pedine coperte
func viewer() -> Array:
	if replaying or ended:
		return [0, 1]
	if local_seats.is_empty():
		return [0, 1]
	return local_seats


# ================================================================ costruzione

func _build() -> void:
	board_area = Control.new()
	board_area.anchor_right = 1.0
	board_area.anchor_bottom = 1.0
	board_area.offset_top = TOP_H
	board_area.offset_right = -PANEL_W
	add_child(board_area)
	board2d = preload("res://scripts/ui/board_2d.gd").new()
	board2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_area.add_child(board2d)
	board3d = preload("res://scripts/ui/board_3d.gd").new()
	board3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_area.add_child(board3d)
	for b in [board2d, board3d]:
		b.hex_clicked.connect(_on_hex_click)
		b.hex_hovered.connect(_on_hover)
	# diario in basso
	var lp := PanelContainer.new()
	var ls := UI.panel_style(Color(0.02, 0.03, 0.08, 0.8), Color(UI.METAL_D, 0.8), 1, 4)
	ls.set_content_margin_all(8)
	lp.add_theme_stylebox_override("panel", ls)
	lp.anchor_top = 1.0
	lp.anchor_bottom = 1.0
	lp.anchor_right = 1.0
	lp.offset_top = -150
	lp.offset_left = 10
	lp.offset_right = -10
	lp.offset_bottom = -10
	lp.mouse_filter = Control.MOUSE_FILTER_PASS
	board_area.add_child(lp)
	log_lbl = RichTextLabel.new()
	log_lbl.bbcode_enabled = true
	log_lbl.scroll_following = true
	log_lbl.add_theme_font_override("normal_font", UI.font_mono)
	log_lbl.add_theme_font_size_override("normal_font_size", 16)
	log_lbl.add_theme_color_override("default_color", UI.CYAN)
	log_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	lp.add_child(log_lbl)
	hover_lbl = UI.label("", 18, UI.YELLOW, UI.font_mono)
	hover_lbl.position = Vector2(16, 8)
	hover_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	hover_lbl.add_theme_constant_override("shadow_offset_x", 2)
	hover_lbl.add_theme_constant_override("shadow_offset_y", 2)
	hover_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_area.add_child(hover_lbl)
	# barra in alto
	var top := PanelContainer.new()
	var ts := UI.panel_style(Color("#0a1024"), UI.METAL, 0, 0)
	ts.border_width_bottom = 2
	ts.set_content_margin_all(6)
	ts.content_margin_left = 14
	top.add_theme_stylebox_override("panel", ts)
	top.anchor_right = 1.0
	top.offset_bottom = TOP_H
	add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	top.add_child(hb)
	hb.add_child(UI.title("DeltaVee", 34))
	var sc := UI.label("%d · %s" % [engine.scn + 1, engine.sc["name"]], 22, UI.PINK, UI.font_bold)
	hb.add_child(sc)
	phase_lbl = UI.label("", 20, UI.TEXT, UI.font_semi)
	phase_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_lbl.clip_text = true
	hb.add_child(phase_lbl)
	status_lbl = UI.label("", 18, UI.YELLOW, UI.font_semi)
	hb.add_child(status_lbl)
	var b3 := UI.button("2D / 3D", 100, 46, 18)
	b3.pressed.connect(func():
		view3d = not view3d
		_apply_view())
	hb.add_child(b3)
	var bc := UI.button("Centra", 90, 46, 18)
	bc.pressed.connect(func():
		board2d.fit()
		board3d.fit())
	hb.add_child(bc)
	var ba := UI.button("Audio sì" if main.audio_on else "Audio no", 104, 46, 18)
	ba.pressed.connect(func():
		main.set_audio(not main.audio_on)
		ba.text = "Audio sì" if main.audio_on else "Audio no")
	hb.add_child(ba)
	# opacità della griglia di esagoni
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", -2)
	gv.alignment = BoxContainer.ALIGNMENT_CENTER
	gv.add_child(UI.label("Griglia", 14, UI.MUTED, UI.font_semi))
	var gs := HSlider.new()
	gs.min_value = 0.0
	gs.max_value = 1.0
	gs.step = 0.05
	gs.custom_minimum_size = Vector2(110, 20)
	gs.value = main.grid_alpha if main != null else 1.0
	gs.focus_mode = Control.FOCUS_NONE
	gs.tooltip_text = "Opacità della griglia di esagoni: a zero restano solo i puntini al centro"
	gs.value_changed.connect(func(v: float):
		board2d.set_grid_alpha(v)
		board3d.set_grid_alpha(v))
	gs.drag_ended.connect(func(_c): main.set_grid_alpha(gs.value))
	gv.add_child(gs)
	hb.add_child(gv)
	var bl := UI.button("Diario", 90, 46, 18)
	bl.pressed.connect(_toggle_log)
	hb.add_child(bl)
	var br := UI.button("Regole", 90, 46, 18)
	br.pressed.connect(_show_rules_popup)
	hb.add_child(br)
	var bm := UI.button("Menu", 80, 46, 18)
	bm.pressed.connect(_confirm_menu)
	hb.add_child(bm)
	# pannello a destra
	var rp := PanelContainer.new()
	var rs := UI.panel_style(Color("#0a1024"), UI.METAL, 0, 0)
	rs.border_width_left = 2
	rs.set_content_margin_all(10)
	rp.add_theme_stylebox_override("panel", rs)
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.anchor_bottom = 1.0
	rp.offset_left = -PANEL_W
	rp.offset_top = TOP_H
	add_child(rp)
	# pannello a schede: intestazione fissa, tre schede, pulsanti di fine fase
	right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	rp.add_child(right)
	head_box = VBoxContainer.new()
	right.add_child(head_box)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 4)
	right.add_child(tb)
	for t in [["ord", "Ordini"], ["car", "Caratteristiche"], ["mod", "Moduli"]]:
		var b := UI.button(t[1], 0, 40, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var k: String = t[0]
		b.pressed.connect(func(): _show_tab(k))
		tb.add_child(b)
		tab_btns[k] = b
	var under := ColorRect.new()
	under.color = UI.STRIPE
	under.custom_minimum_size = Vector2(0, 3)
	right.add_child(under)
	for k in ["ord", "car", "mod"]:
		var tsc := ScrollContainer.new()
		tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right.add_child(tsc)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 7)
		tsc.add_child(vb)
		tab_scroll[k] = tsc
		match k:
			"ord":
				act_box = vb
			"car":
				car_box = vb
			"mod":
				mod_box = vb
	foot_box = VBoxContainer.new()
	foot_box.add_theme_constant_override("separation", 6)
	right.add_child(foot_box)
	_show_tab("ord")


func _apply_view() -> void:
	board2d.visible = not view3d
	board3d.visible = view3d
	live_dirty = true
	_push_state()


func _toggle_log() -> void:
	if is_instance_valid(log_full):
		log_full.queue_free()
		return
	log_full = PanelContainer.new()
	log_full.add_theme_stylebox_override("panel", UI.dark_style(6, 0.97))
	log_full.anchor_right = 1.0
	log_full.anchor_bottom = 1.0
	log_full.offset_left = 40
	log_full.offset_top = TOP_H + 30
	log_full.offset_right = -PANEL_W - 40
	log_full.offset_bottom = -30
	add_child(log_full)
	var vb := VBoxContainer.new()
	log_full.add_child(vb)
	var hh := HBoxContainer.new()
	vb.add_child(hh)
	var t := UI.title("Diario di bordo", 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(t)
	var x := UI.button("Chiudi", 120)
	x.pressed.connect(_toggle_log)
	hh.add_child(x)
	var rt := RichTextLabel.new()
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.add_theme_font_override("normal_font", UI.font_mono)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_color_override("default_color", UI.CYAN)
	vb.add_child(rt)
	for l in engine.log_lines:
		rt.append_text(_fmt_log(l) + "\n")


func _fmt_log(t: String) -> String:
	if t.begins_with("—"):
		return "[color=#f4e46a]%s[/color]" % t
	if "COLPITO" in t or "distrutto" in t or "intercetta " in t:
		return "[color=#ff9a4a]%s[/color]" % t
	if t.begins_with("Vince") or t.begins_with("Pareggio"):
		return "[color=#ef6f9c]%s[/color]" % t
	return t


func _on_log(t: String) -> void:
	log_lbl.append_text(_fmt_log(t) + "\n")


# ================================================================ stato e animazioni

var _wait_text := ""

func _mark() -> void:
	live_dirty = true
	_refresh_labels()
	# mentre gioca l'altro lato (IA o avversario online) il pannello lo dice
	if pending.is_empty() and not ended and not replaying and engine.phase != "over":
		var t := "%s · %s" % [engine.pname(engine.current), {"setup": "schieramento", "move": "movimento", "cmd": "comandi", "fire": "fuoco"}.get(engine.phase, "")]
		if t != _wait_text:
			_wait_text = t
			_clear_box()
			var w := UI.title("Attendere…", 28, UI.MUTED)
			act_box.add_child(w)
			_txt("Sta giocando: %s." % t, UI.SIDE[engine.current], 19, UI.font_semi)
	else:
		_wait_text = ""


func _on_resumed() -> void:
	status_lbl.text = "Partita ripresa dal turno %d." % engine.turn
	live_dirty = true
	_refresh()


func _on_fx(kind: String, data: Dictionary) -> void:
	if kind == "destroyed" or engine.resuming:
		return
	if tutor != null:
		if kind == "launch":
			tutor.event("launch")
		elif kind == "fire" and data.get("hit", false) and int(engine.reg.get(str(data.get("a", "")), {}).get("side", 0)) == 1:
			tutor.event("hit_me")
	anim_idx = engine.history.size() - 1
	anim_t0 = Time.get_ticks_msec() / 1000.0
	_seg_sound(data, 1.0 / maxf(0.1, engine.anim))


const WSND := {"lb": "laser", "lbb": "laser_sbarramento", "pb": "particelle", "pbb": "particelle_sbarramento"}

## suoni di un segmento della partita (k = scala dei tempi)
func _seg_sound(seg: Dictionary, k: float) -> void:
	if main == null or engine.headless:
		return
	match str(seg.get("k", "")):
		"fire":
			var w := str(seg.get("w", "lb"))
			main.sfx(WSND.get(w, "laser"), -4.0)
			var pt: Array = FX2D.pattern(w)
			var arrive: float = float(pt[1]) * (int(pt[0]) - 1) + float(pt[2])
			main.sfx("impatto" if seg.get("hit", false) else "mancato", -3.0, arrive * k)
		"boom":
			main.sfx("esplosione", 0.0)
		"launch":
			main.sfx("missile", -4.0)
		"jump":
			main.sfx("salto", -2.0)
		"move":
			if int(seg.get("steps", 0)) > 0:
				main.sfx("motori", -10.0)
			var steps := maxi(1, int(seg.get("steps", 1)))
			var dur := Timeline.duration(seg) * k
			for ev in seg.get("ev", []):
				var at := dur * float(ev.get("step", 0)) / steps
				if ev["k"] == "boom":
					main.sfx("intercetta", -6.0, at)
					main.sfx("esplosione", 0.0, at + 0.05)


func _process(_d: float) -> void:
	if replaying:
		_replay_step(_d)
		return
	if anim_idx >= 0 and anim_idx < engine.history.size():
		var dur := Timeline.duration(engine.history[anim_idx]) / maxf(0.1, engine.anim)
		var t := (Time.get_ticks_msec() / 1000.0 - anim_t0) / dur
		if t < 1.0:
			var st := Timeline.state_at(engine.history, anim_idx, t, engine.reg)
			_set_state(st)
			return
		anim_idx = -1
		live_dirty = true
	if live_dirty:
		live_dirty = false
		_push_state()


func _push_state() -> void:
	if replaying:
		return
	_set_state(Timeline.from_snapshot(engine.snapshot(), engine.reg, engine.maps))


func _set_state(st: Dictionary) -> void:
	var b = board3d if view3d else board2d
	b.viewer = viewer()
	b.ov = _overlay() if not replaying else {}
	b.set_state(st)


func _refresh() -> void:
	_refresh_labels()
	_card()
	live_dirty = true


func _refresh_labels() -> void:
	if not is_instance_valid(phase_lbl):
		return
	var ph: String = {"setup": "Schieramento", "move": "Movimento", "cmd": "Comando", "fire": "Fuoco", "over": "Partita finita"}.get(engine.phase, "")
	var who := engine.pname(engine.phasing)
	phase_lbl.text = "Turno %d  ·  %s  ·  %s" % [maxi(1, engine.turn), ph, who] if engine.phase != "over" else "Partita finita"
	if engine.scn == 4:
		phase_lbl.text += "   ·   Punti %d – %d" % [engine.vp[0], engine.vp[1]]
	phase_lbl.add_theme_color_override("font_color", UI.SIDE[engine.phasing] if engine.phase != "over" else UI.YELLOW)


# ================================================================ scheda dell'unità (Spaceship Log)

var _card_sel := ""


func _card() -> void:
	for box in [head_box, car_box, mod_box]:
		for c in box.get_children():
			c.queue_free()
	var w := PANEL_W - 24
	if sel != _card_sel:
		pod_detail = -1
		_card_sel = sel
	if sel == "" or not engine.units.has(sel):
		var hint := UI.label("Nessuna unità scelta: tocca una pedina sulla mappa per vederne la scheda.", 17, UI.MUTED, UI.font_semi)
		head_box.add_child(UI.wrap(hint, w))
		car_box.add_child(UI.wrap(UI.label("Tocca una pedina sulla mappa per vederne le caratteristiche.", 17, UI.MUTED), w))
		_legend()
		mod_box.add_child(UI.wrap(UI.label("Tocca un'astronave per vederne i moduli.", 17, UI.MUTED), w))
		_tab_state(false)
		return
	var u: Dictionary = engine.units[sel]
	var mine: bool = u["side"] in viewer()
	var hidden: bool = not u["rev"] and not mine
	var full: bool = mine or ended or replaying
	head_box.add_child(ShipCard.header(engine, u, hidden, full, w))
	car_box.add_child(ShipCard.stats(engine, u, hidden, full, w))
	var has_pods: bool = not hidden and u["kind"] == "ship" and not u["pods"].is_empty()
	if has_pods:
		mod_box.add_child(ShipCard.pods(engine, u, full, w, pod_detail, func(i: int):
			pod_detail = i
			_card()))
	else:
		mod_box.add_child(UI.wrap(UI.label("Questa unità non ha moduli.", 17, UI.MUTED), w))
	_tab_state(has_pods)


func _tab_state(has_pods: bool) -> void:
	tab_btns["mod"].disabled = not has_pods
	if tab == "mod" and not has_pods:
		_show_tab("car")


func _show_tab(k: String) -> void:
	tab = k
	for t in tab_scroll:
		tab_scroll[t].visible = t == k
		var b: Button = tab_btns[t]
		if t == k:
			for st in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(st, UI._btn(Color("#3a2a14"), UI.YELLOW))
			b.add_theme_color_override("font_color", UI.YELLOW)
			b.add_theme_color_override("font_hover_color", UI.YELLOW)
		else:
			for st in ["normal", "hover", "pressed", "focus"]:
				b.remove_theme_stylebox_override(st)
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_hover_color")


func _legend() -> void:
	var t := "[b]Come si legge la mappa[/b]\n• Ogni pedina punta nella sua direzione (ore dell'orologio); il quadratino grigio è la velocità.\n• Ore pari = verso un lato dell'esagono, ore dispari = verso un vertice: lì il movimento procede a zig-zag.\n• Pedine coperte (freccia) = caccia e missili nemici non ancora individuati.\n• Cerchio azzurro = campo di forza attivo; «+n» = missili o caccia pronti sopra la nave."
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = t
	rt.custom_minimum_size = Vector2(PANEL_W - 30, 0)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.add_theme_color_override("default_color", UI.MUTED)
	car_box.add_child(rt)


# ================================================================ selezione e clic

func _on_hover(h: Vector2i) -> void:
	if replaying:
		return
	if is_instance_valid(hover_lbl):
		var t := engine.hcode(h)
		var names := []
		for u in engine.units_at(h):
			names.append(engine.uname_for(u, viewer()[0] if viewer().size() == 1 else u["side"]))
		if engine.is_planet(h):
			names.append("pianeta %s" % engine.sc.get("planet_name", ""))
		elif engine.is_asteroid(h):
			names.append("asteroidi")
		hover_lbl.text = t + ("  ·  " + ", ".join(names) if not names.is_empty() else "")
	var b = board3d if view3d else board2d
	b.redraw()


func _on_hex_click(h: Vector2i) -> void:
	if replaying:
		return
	# modalità speciali (scarto, lancio, bersaglio, schieramento)
	if not pending.is_empty() and _mode_click(h):
		_redraw_all()
		return
	var here := engine.units_at(h)
	for id in engine.order:
		var u: Dictionary = engine.units[id]
		if u["st"] in ["prep"] and engine.units.has(u.get("host", "")) and engine.units[u["host"]]["st"] == "on" and engine.units[u["host"]]["hex"] == h:
			if u["side"] in viewer():
				here.append(u)
	if here.is_empty():
		return
	var i: int = _click_cycle.get(h, -1) + 1
	if i >= here.size():
		i = 0
	_click_cycle = {h: i}
	select(here[i]["id"])


func select(id: String) -> void:
	sel = id
	if pending.is_empty() and tab == "ord" and id != "":
		_show_tab("car")
	if pending.get("type", "") in ["cmd", "fire"]:
		mode = ""
		aux = {}
		_build_decision()
	_card()
	_redraw_all()


func _redraw_all() -> void:
	live_dirty = true
	_push_state()


# ================================================================ sovrapposizioni

func _overlay() -> Dictionary:
	var o := {"sel": sel, "hl": {}, "paths": [], "arrows": [], "targets": {}, "labels": {}}
	var t := str(pending.get("type", ""))
	if t == "cmd":
		for id in plan.get("m", {}).keys() + ([sel] if sel != "" else []):
			if not engine.units.has(id):
				continue
			var u: Dictionary = engine.units[id]
			if u["st"] != "on" or u["side"] != int(pending["seat"]):
				continue
			var pr := _preview(u)
			o["paths"].append({"from": pr[0], "hexes": pr[1], "ghost": {"hex": pr[1][-1] if not pr[1].is_empty() else pr[0], "dir": pr[2]},
				"col": UI.YELLOW if id == sel else Color(UI.SIDE[u["side"]], 0.8)})
		if mode == "weave" and engine.units.has(sel):
			for h in _weave_hexes(engine.units[sel]):
				o["hl"][h] = UI.CYAN
		if mode == "launchbc" and engine.units.has(sel):
			var u: Dictionary = engine.units[sel]
			for h in Hex.neighbors(u["hex"]):
				o["hl"][h] = UI.CYAN if aux.get("hex", null) != h else UI.YELLOW
			if aux.has("hex"):
				o["arrows"].append([aux["hex"], _bc_dirs(u), aux.get("dir", -1)])
		if mode == "tractor" and engine.units.has(sel):
			for tu in _tractor_targets(engine.units[sel]):
				o["targets"][tu["id"]] = "traente"
	elif t == "fire":
		if engine.units.has(sel) and aux.has("w"):
			var u: Dictionary = engine.units[sel]
			for tt in engine.valid_targets(int(pending["seat"])):
				var tv := engine.target_value(u, aux["src"], tt)
				var ch := engine.hit_chance(aux["w"], tv["tv"])
				o["targets"][tt["id"]] = ("%d%%" % mini(100, ch * 10)) if ch > 0 else "—"
		if mode == "launch" and engine.units.has(sel):
			var u: Dictionary = engine.units[sel]
			for sp in engine.launch_spots(u):
				o["hl"][sp[0]] = UI.YELLOW if aux.get("hex", null) == sp[0] else UI.CYAN
				if aux.get("hex", null) == sp[0]:
					o["arrows"].append([sp[0], sp[1], aux.get("dir", -1)])
					var mm := {"hex": sp[0], "dir": aux.get("dir", sp[1][1]), "zig": 0}
					var vv := int(aux.get("v", 1)) + (1 if aux.get("mt", "") == "ug" else 0)
					var pth := Hex.path(sp[0], mm["dir"], 0, vv)
					o["paths"].append({"from": sp[0], "hexes": pth[0], "col": UI.PINK})
	elif t == "deploy":
		var cur: String = aux.get("ship", "")
		for s in pending["ships"]:
			if s["id"] == cur:
				for h in s["allowed"]:
					o["hl"][h] = UI.CYAN
		for id in plan.get("hex", {}):
			o["labels"][plan["hex"][id]] = engine.units[id]["label"]
	elif t == "planet":
		var u: Dictionary = engine.units[pending["u"]]
		o["sel"] = u["id"]
	return o


## anteprima del movimento con gli ordini in preparazione: [partenza, esagoni, direzione]
func _preview(u: Dictionary) -> Array:
	var o: Dictionary = plan.get("m", {}).get(u["id"], {})
	var h: Vector2i = o.get("w", u["hex"]) if o.get("w", null) != null else u["hex"]
	var d := posmod(int(u["dir"]) + int(o.get("t", 0)), 12)
	var z: int = 0 if int(o.get("t", 0)) != 0 else int(u["zig"])
	var v := clampi(int(u["v"]) + int(o.get("a", 0)), 0, 9)
	if u["kind"] == "mis" and u["cls"] == "ug":
		v = int(u["v"])
	if int(u.get("jump", 0)) == 2 or str(o.get("j", "")) == "jump":
		return [h, [], d]
	var p := Hex.path(h, d, z, v)
	return [h, p[0], d]


# ================================================================ decisioni

func _on_decision(req: Dictionary) -> void:
	pending = req
	_show_tab("ord")
	_wait_text = ""
	plan = {}
	mode = ""
	aux = {}
	match str(req["type"]):
		"cmd":
			plan = {"m": {}, "b": []}
			var mine := _own_units(int(req["seat"]))
			if not mine.is_empty() and (sel == "" or not engine.units.has(sel) or engine.units[sel]["side"] != int(req["seat"]) or engine.units[sel]["st"] != "on"):
				sel = mine[0]["id"]
		"fire":
			var mine := _fire_units(int(req["seat"]))
			if not mine.is_empty() and (sel == "" or not engine.fire_budget.has(sel)):
				sel = mine[0]["id"]
			# si riprende l'arma appena usata, se può sparare ancora
			if _last_fire.get("sel", "") == sel and engine.units.has(sel):
				var u: Dictionary = engine.units[sel]
				var src = _last_fire["src"]
				if engine.src_available(u, src) and _last_fire["w"] in engine.weapons_of(u, src) and engine.energy(u) >= engine.fire_cost(u, _last_fire["w"]):
					aux = {"src": src, "w": _last_fire["w"], "t": ""}
		"deploy":
			plan = {"hex": {}, "dir": {}, "v": 0}
			for s in req["ships"]:
				var u: Dictionary = engine.units[s["id"]]
				plan["dir"][s["id"]] = u["dir"]
			var sug = engine.ais[int(req["seat"])].decide(engine, int(req["seat"]), req)
			if sug is Dictionary:
				plan["hex"] = sug["hex"].duplicate()
				plan["v"] = int(sug.get("v", 0))
			if not req.get("vrange", []).is_empty():
				plan["v"] = clampi(int(plan["v"]), int(req["vrange"][0]), int(req["vrange"][1]))
			aux = {"ship": req["ships"][0]["id"]}
		"planet":
			plan = {"a": 0, "t": 0}
	status_lbl.text = "Tocca a te: %s" % engine.pname(int(req["seat"])) if local_seats.size() > 1 else "Tocca a te"
	_build_decision()
	_card()
	_redraw_all()
	if tutor != null:
		tutor.event("dec_" + str(req["type"]))


func _submit(r) -> void:
	pending = {}
	plan = {}
	mode = ""
	aux = {}
	status_lbl.text = ""
	_clear_box()
	engine.provide_decision(r)
	_card()
	_redraw_all()


func _clear_box() -> void:
	for c in act_box.get_children():
		c.queue_free()
	for c in foot_box.get_children():
		c.queue_free()


## riga di pulsanti nella fascia fissa in basso
func _foot_row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	foot_box.add_child(h)
	return h


func _own_units(side: int) -> Array:
	var out := []
	for u in engine.live_units(side, "ship") + engine.live_units(side, "bc") + engine.live_units(side, "mis"):
		if u["kind"] == "mis" and u["cls"] == "ug":
			continue
		out.append(u)
	return out


func _fire_units(side: int) -> Array:
	var out := []
	for id in engine.fire_budget:
		var u: Dictionary = engine.units[id]
		if u["st"] == "on" and (not engine.fire_sources(u).is_empty() or not engine.launchable(u).is_empty()):
			out.append(u)
	for m in engine.live_units(side, "mis"):
		if m["cls"] == "m" and not m.get("mims_used", false):
			out.append(m)
	return out


func _txt(t: String, col := UI.TEXT, size := 16, font: Font = null) -> Label:
	var l := UI.label(t, size, col, font if font != null else UI.font_body)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL_W - 30
	act_box.add_child(l)
	return l


func _btn(t: String, cb: Callable, primary := false, w := 0.0, parent: Control = null) -> Button:
	var b := UI.button(t, w, 38, 17)
	if primary:
		UI.primary(b)
	b.pressed.connect(func(): main.sfx("clic", -8.0))
	b.pressed.connect(cb)
	if w == 0.0:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parent if parent != null else act_box).add_child(b)
	return b


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	act_box.add_child(h)
	return h


func _build_decision() -> void:
	_clear_box()
	if pending.is_empty():
		return
	var head := UI.title({"cmd": "Fase di comando", "fire": "Fase di fuoco", "deploy": "Schieramento", "planet": "Gravità del pianeta", "hitpart": "Parte colpita"}.get(pending["type"], ""), 26)
	act_box.add_child(head)
	match str(pending["type"]):
		"cmd":
			_build_cmd()
		"fire":
			_build_fire()
		"deploy":
			_build_deploy()
		"planet":
			_build_planet()
		"hitpart":
			_build_hitpart()


# ---------------------------------------------------------------- unità della fase

func _unit_strip(units: Array, mark: Callable) -> void:
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	act_box.add_child(g)
	for u in units:
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.icon = UI.counter_tex(u["side"], u["kind"], u["cls"], u["label"])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = str(mark.call(u))
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = engine.uname(u)
		if u["id"] == sel:
			b.add_theme_stylebox_override("normal", UI._btn(Color("#3a2a14"), UI.YELLOW))
		var id: String = u["id"]
		b.pressed.connect(func(): select(id))
		g.add_child(b)


# ---------------------------------------------------------------- comandi

func _order(id: String) -> Dictionary:
	if not plan["m"].has(id):
		plan["m"][id] = {"a": 0, "t": 0, "w": null, "j": ""}
	return plan["m"][id]


func _bc_used(sid: String) -> int:
	var n := 0
	for b in plan["b"]:
		if b["s"] == sid:
			n += 1
	return n


func _has_guide(mid: String) -> bool:
	for b in plan["b"]:
		if b["k"] == "guide" and b["mis"] == mid:
			return true
	return false


func _build_cmd() -> void:
	var side := int(pending["seat"])
	_txt("Date gli ordini a ogni unità: le manovre (velocità, direzione, scarto) e i comandi di battaglia. La linea gialla mostra il prossimo movimento.", UI.MUTED, 16)
	var units := _own_units(side)
	_unit_strip(units, func(u):
		var o: Dictionary = plan["m"].get(u["id"], {})
		var any: bool = int(o.get("a", 0)) != 0 or int(o.get("t", 0)) != 0 or o.get("w", null) != null or str(o.get("j", "")) != ""
		return ("• " if any or _bc_used(u["id"]) > 0 else "") + u["label"])
	if sel == "" or not engine.units.has(sel):
		_cmd_footer()
		return
	var u: Dictionary = engine.units[sel]
	if u["side"] != side or u["st"] != "on":
		_txt("Scegliete una vostra unità.", UI.MUTED)
		_cmd_footer()
		return
	_cmd_maneuver(u)
	if u["kind"] == "ship":
		_cmd_battle(u)
	_cmd_footer()


func _cmd_maneuver(u: Dictionary) -> void:
	var o := _order(u["id"])
	if u["kind"] == "ship" and engine.sc.has("jump_from") and u["side"] == 0 and engine.has_pod_type(u, ["jump", "hunter", "ajump"], 1) >= 0:
		var r := _row()
		var j := int(u["jump"])
		if j == 0:
			var b := _btn("Prepara il salto" if str(o["j"]) != "prep" else "• Salto in preparazione (annulla)", func():
				o["j"] = "" if str(o["j"]) == "prep" else "prep"
				_rebuild(), false, 0, r)
			b.tooltip_text = "Si può saltare solo dalla mappa E (a destra della D) o da quelle sopra e sotto."
		elif j == 1:
			_btn("• Salta!" if str(o["j"]) == "jump" else "Salta!", func():
				o["j"] = "jump"
				_rebuild(), true, 0, r)
			_btn("Annulla il salto", func():
				o["j"] = "abort"
				_rebuild(), false, 0, r)
		else:
			_txt("Salto avviato: la nave lascerà il campo nel prossimo movimento.", UI.YELLOW)
	if u["kind"] == "mis" and u["cls"] == "g" and not _has_guide(u["id"]):
		var host: Dictionary = engine.units.get(u.get("host", ""), {})
		if host.is_empty() or host["st"] != "on":
			_txt("Missile guidato senza nave di controllo: prosegue dritto.", UI.MUTED)
			return
		var free := engine.bc_count(host) - _bc_used(host["id"])
		_txt("Per manovrarlo serve un comando di battaglia di %s (liberi: %d)." % [engine.uname(host), free], UI.MUTED)
		if free > 0 and engine.pod_state(host, int(u["pod"])) < 2:
			_btn("Guida questo missile", func():
				plan["b"].append({"s": host["id"], "k": "guide", "mis": u["id"]})
				_rebuild())
		return
	if not engine.can_maneuver(u):
		var why := "Non può ricevere comandi di manovra"
		if u.get("ffon", false):
			why += " (campo di forza attivo)"
		elif int(u.get("jump", 0)) > 0:
			why += " (salto in corso)"
		elif u["kind"] == "mis":
			why += " (energia esaurita)"
		elif engine.part_state(u, "engine") == 3:
			why += " (motore distrutto)"
		elif not u.get("alerted", true):
			why += " (non ancora allertata)"
		_txt(why + ".", UI.MUTED)
		return
	var lim := engine.man_limits(u)
	var a := int(o["a"])
	var t := int(o["t"])
	var w = o["w"]
	var used := absi(a) + absi(t) + (1 if w != null else 0)
	var n: int = lim["n"]
	var cost := engine.man_cost(u, a, t, w != null)
	var unit := "blocchi" if u["kind"] == "ship" else "unità"
	_txt("Comandi di manovra: %d su %d · costo: %d %s%s" % [used, n, cost, unit,
		(" (%d unità)" % (cost * engine.burn(u))) if u["kind"] == "ship" and cost > 0 else ""], UI.CYAN, 18, UI.font_semi)
	if lim["single"]:
		_txt("La velocità è pari o superiore alla manovra: è permesso un solo accelera o decelera.", UI.PINK, 16)
	if not engine.can_pay(u, cost):
		_txt("Energia insufficiente per questi ordini!", UI.RED, 17)
	var r1 := _row()
	r1.add_child(UI.label("Velocità", 19, UI.TEXT, UI.font_semi))
	var nv := clampi(int(u["v"]) + a, 0, 9)
	var bm := _btn("−", func():
		o["a"] = a - 1
		_rebuild(), false, 54, r1)
	bm.disabled = nv <= (1 if u["kind"] == "mis" else 0) or a <= -int(lim["vr"]) or (used >= n and a <= 0)
	var vl := UI.label("da %d a %d" % [u["v"], nv], 24, UI.YELLOW, UI.font_bold)
	vl.custom_minimum_size.x = 90
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r1.add_child(vl)
	var bp := _btn("+", func():
		o["a"] = a + 1
		_rebuild(), false, 54, r1)
	bp.disabled = nv >= 9 or a >= int(lim["vr"]) or (used >= n and a >= 0)
	r1.add_child(UI.label("  (±%d per fase)" % lim["vr"], 16, UI.MUTED))
	var r2 := _row()
	r2.add_child(UI.label("Direzione", 19, UI.TEXT, UI.font_semi))
	var nd := posmod(int(u["dir"]) + t, 12)
	var bl := _btn("Sx", func():
		o["t"] = t - 1
		_rebuild(), false, 54, r2)
	bl.disabled = lim["single"] or (used >= n and t <= 0)
	var dl := UI.label("da ore %s a ore %s" % [D.DIR_NAMES[u["dir"]], D.DIR_NAMES[nd]], 22, UI.YELLOW, UI.font_bold)
	dl.custom_minimum_size.x = 150
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r2.add_child(dl)
	var br := _btn("Dx", func():
		o["t"] = t + 1
		_rebuild(), false, 54, r2)
	br.disabled = lim["single"] or (used >= n and t >= 0)
	if u["kind"] != "mis":
		var r3 := _row()
		var can_w: bool = not lim["single"] and engine.part_state(u, "bridge") < 2 and (used < n or w != null)
		if w == null:
			var bw := _btn("Scarto laterale (1 blocco)" if mode != "weave" else "Tocca un esagono azzurro…", func():
				mode = "weave" if mode != "weave" else ""
				_rebuild(), mode == "weave", 0, r3)
			bw.disabled = not can_w
		else:
			_btn("Annulla lo scarto (in %s)" % engine.hcode(w), func():
				o["w"] = null
				_rebuild(), false, 0, r3)
	var r4: HBoxContainer = act_box.get_child(act_box.get_child_count() - 1) if u["kind"] != "mis" else _row()
	_btn("Azzera unità", func():
		plan["m"].erase(u["id"])
		mode = ""
		_rebuild(), false, 0, r4)


func _weave_hexes(u: Dictionary) -> Array:
	var out := []
	for h in Hex.neighbors(u["hex"]):
		if not engine.is_planet(h) and not engine.is_asteroid(h):
			out.append(h)
	return out


func _cmd_battle(u: Dictionary) -> void:
	var n := engine.bc_count(u)
	var used := _bc_used(u["id"])
	act_box.add_child(UI.heading("Comandi di battaglia: %d su %d" % [used, n], 19, UI.CYAN))
	if n == 0:
		_txt("Questa nave non ha moduli che danno comandi di battaglia (armi leggere, pesanti, arsenale, comunicazioni).", UI.MUTED, 16)
	for i in plan["b"].size():
		var b: Dictionary = plan["b"][i]
		if b["s"] != u["id"]:
			continue
		var r := _row()
		var l := UI.label("• " + _bc_text(b), 17, UI.YELLOW, UI.font_semi)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		var idx: int = i
		_btn("×", func():
			plan["b"].remove_at(idx)
			_rebuild(), false, 44, r)
	if used >= n:
		return
	var ffon: bool = u.get("ffon", false)
	var queued_ff := false
	for b in plan["b"]:
		if b["s"] == u["id"] and b["k"] in ["ffon", "ffoff"]:
			queued_ff = true
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	act_box.add_child(g)
	var add := func(t: String, cmd: Dictionary, enabled := true):
		var b := UI.button(t, (PANEL_W - 40) / 2, 42, 16)
		b.disabled = not enabled
		b.pressed.connect(func():
			plan["b"].append(cmd)
			_rebuild())
		g.add_child(b)
	# preparazione dei missili
	var have := engine.prepared_of(u).size()
	for b in plan["b"]:
		if b["s"] == u["id"] and b["k"] == "prep":
			have += 1
	for i in u["pods"].size():
		var p: Dictionary = u["pods"][i]
		var pd: Dictionary = D.PODS[p["t"]]
		if not pd["lp"] or engine.pod_state(u, i) >= 2:
			continue
		for mt in pd["prep"]:
			var avail := int(p["ms"].get(mt, 0))
			for b in plan["b"]:
				if b["s"] == u["id"] and b["k"] == "prep" and int(b["pod"]) == i and b["mt"] == mt:
					avail -= 1
			if avail > 0:
				add.call("Prepara %s (mod. %d)" % [D.MNAME[mt], i + 1], {"s": u["id"], "k": "prep", "pod": i, "mt": mt}, have < engine.missile_pods(u))
	if not ffon:
		add.call("Ricerca attiva", {"s": u["id"], "k": "search"})
	else:
		add.call("Ricerca attiva", {"s": u["id"], "k": "search"})
	if engine.ff_class(u) > 0 and not queued_ff:
		if ffon:
			add.call("Spegni campo di forza", {"s": u["id"], "k": "ffoff"})
		else:
			add.call("Attiva campo di forza", {"s": u["id"], "k": "ffon"}, engine.can_pay(u, 1))
	for i in u["pods"].size():
		var p: Dictionary = u["pods"][i]
		if p["t"] != "bcpod" or p["bc"] == "" or engine.pod_state(u, i) >= 2:
			continue
		var bc: Dictionary = engine.units[p["bc"]]
		if bc["st"] == "dock":
			add.call("Prepara caccia %s" % bc["label"], {"s": u["id"], "k": "prepbc", "pod": i})
		elif bc["st"] == "prep" and int(bc["prep_at"]) < engine.cmd_round and not ffon:
			var pi: int = i
			var b := UI.button("Lancia caccia %s…" % bc["label"], (PANEL_W - 40) / 2, 42, 16)
			b.pressed.connect(func():
				mode = "launchbc"
				aux = {"pod": pi, "v": maxi(1, int(u["v"])), "dir": u["dir"]}
				_rebuild())
			g.add_child(b)
		elif bc["st"] == "on" and bc["hex"] == u["hex"] and bc["v"] == u["v"] and bc["dir"] == u["dir"] and not ffon:
			add.call("Fai rientrare %s" % bc["label"], {"s": u["id"], "k": "dock", "bc": bc["id"]})
	if not ffon:
		var tp := engine.has_pod_type(u, ["tractor"], 1)
		if tp >= 0:
			var b := UI.button("Raggio traente…", (PANEL_W - 40) / 2, 42, 16)
			b.pressed.connect(func():
				mode = "tractor"
				aux = {"pod": tp, "a": 0, "tt": 0}
				_rebuild())
			g.add_child(b)
		for t in engine.live_units(-1, "ship"):
			if t["id"] != u["id"] and t["hex"] == u["hex"]:
				add.call("Aggancio con %s" % t["label"], {"s": u["id"], "k": "rdv", "t": t["id"]}, t["v"] == u["v"] and t["dir"] == u["dir"])
	# sotto-modalità
	if mode == "launchbc":
		_txt("Lancio del caccia: tocca un esagono adiacente, poi scegli direzione e velocità.", UI.YELLOW, 16)
		if aux.has("hex"):
			var r := _row()
			r.add_child(UI.label("Direzione", 18))
			for d in _bc_dirs(u):
				var dd: int = d
				var b := _btn(D.DIR_NAMES[d], func():
					aux["dir"] = dd
					_rebuild(), aux.get("dir", -1) == d, 50, r)
			var r2 := _row()
			r2.add_child(UI.label("Velocità", 18))
			for v in _bc_vels(u):
				var vv: int = v
				_btn(str(v), func():
					aux["v"] = vv
					_rebuild(), aux.get("v", -1) == v, 50, r2)
			_btn("Conferma il lancio", func():
				plan["b"].append({"s": u["id"], "k": "launchbc", "pod": aux["pod"], "hex": aux["hex"], "v": aux["v"], "dir": aux["dir"]})
				mode = ""
				aux = {}
				_rebuild(), true)
	if mode == "tractor":
		var civ: int = u["pods"][aux["pod"]]["civ"]
		var maxc := 2 if civ >= 8 else 1
		_txt("Raggio traente (civiltà %d): tocca una nave o un caccia entro %d esagoni, poi %d comando/i di manovra. Costa 2 × il blocco del bersaglio per comando." % [civ, 6 if civ >= 8 else 4, maxc], UI.YELLOW, 16)
		if aux.has("t"):
			var tu: Dictionary = engine.units[aux["t"]]
			_txt("Bersaglio: %s (vel. %d, ore %s)" % [engine.uname_for(tu, u["side"]), tu["v"], D.DIR_NAMES[tu["dir"]]], UI.TEXT, 17)
			var r := _row()
			for spec in [["−vel", "a", -1], ["+vel", "a", 1], ["Vira sx", "tt", -1], ["Vira dx", "tt", 1]]:
				var key: String = spec[1]
				var dv: int = spec[2]
				_btn(spec[0], func():
					var na := int(aux["a"]) + (dv if key == "a" else 0)
					var nt := int(aux["tt"]) + (dv if key == "tt" else 0)
					if absi(na) + absi(nt) <= maxc:
						aux["a"] = na
						aux["tt"] = nt
					_rebuild(), false, 0, r)
			_txt("Ordine: velocità %+d, direzione %+d" % [aux["a"], aux["tt"]], UI.CYAN, 17)
			_btn("Conferma il raggio traente", func():
				plan["b"].append({"s": u["id"], "k": "tractor", "pod": aux["pod"], "t": aux["t"], "a": aux["a"], "tt": aux["tt"]})
				mode = ""
				aux = {}
				_rebuild(), true)


func _bc_dirs(u: Dictionary) -> Array:
	var out := []
	for k in range(-2, 3):
		out.append(posmod(int(u["dir"]) + k, 12))
	return out


func _bc_vels(u: Dictionary) -> Array:
	var out := []
	for k in [-1, 0, 1]:
		var v: int = maxi(1, int(u["v"]) + k)
		if not v in out:
			out.append(v)
	return out


func _tractor_targets(u: Dictionary) -> Array:
	var out := []
	var tp := engine.has_pod_type(u, ["tractor"], 1)
	if tp < 0:
		return out
	var rr := 6 if int(u["pods"][tp]["civ"]) >= 8 else 4
	for t in engine.live_units(-1, "ship") + engine.live_units(-1, "bc"):
		if t["id"] != u["id"] and Hex.dist(t["hex"], u["hex"]) <= rr:
			out.append(t)
	return out


func _bc_text(b: Dictionary) -> String:
	match b["k"]:
		"prep":
			return "Prepara %s (modulo %d)" % [D.MNAME[b["mt"]], int(b["pod"]) + 1]
		"guide":
			return "Guida %s" % engine.units[b["mis"]]["label"]
		"search":
			return "Ricerca attiva"
		"prepbc":
			return "Prepara il caccia"
		"launchbc":
			return "Lancia il caccia in %s" % engine.hcode(b["hex"])
		"dock":
			return "Rientro del caccia"
		"rdv":
			return "Aggancio"
		"tractor":
			return "Raggio traente su %s" % engine.units[b["t"]]["label"]
		"ffon":
			return "Attiva il campo di forza"
		"ffoff":
			return "Spegni il campo di forza"
	return b["k"]


func _cmd_footer() -> void:
	var r := _foot_row()
	_btn("Suggerisci (IA)", func():
		var s = engine.ais[int(pending["seat"])].decide(engine, int(pending["seat"]), pending)
		if s is Dictionary:
			plan = {"m": {}, "b": s.get("b", [])}
			for id in s.get("m", {}):
				var o: Dictionary = s["m"][id]
				plan["m"][id] = {"a": int(o.get("a", 0)), "t": int(o.get("t", 0)), "w": o.get("w", null), "j": str(o.get("j", ""))}
		_rebuild(), false, 0, r)
	_btn("Azzera tutto", func():
		plan = {"m": {}, "b": []}
		mode = ""
		_rebuild(), false, 0, r)
	var rf := _foot_row()
	_btn("Fine comandi", func():
		var m := {}
		for id in plan["m"]:
			var o: Dictionary = plan["m"][id]
			if int(o["a"]) != 0 or int(o["t"]) != 0 or o["w"] != null or str(o["j"]) != "":
				m[id] = o
		_submit({"m": m, "b": plan["b"]}), true, 0, rf)


func _rebuild() -> void:
	_build_decision()
	_redraw_all()


func _mode_click(h: Vector2i) -> bool:
	var t := str(pending.get("type", ""))
	if t == "cmd" and engine.units.has(sel):
		var u: Dictionary = engine.units[sel]
		if mode == "weave":
			if h in _weave_hexes(u):
				_order(u["id"])["w"] = h
				mode = ""
				_build_decision()
				return true
			mode = ""
			_build_decision()
			return false
		if mode == "launchbc":
			if Hex.dist(h, u["hex"]) == 1:
				aux["hex"] = h
				_build_decision()
				return true
			return false
		if mode == "tractor":
			for tu in _tractor_targets(u):
				if tu["hex"] == h:
					aux["t"] = tu["id"]
					aux["a"] = 0
					aux["tt"] = 0
					_build_decision()
					return true
			return false
	if t == "fire" and engine.units.has(sel):
		var u: Dictionary = engine.units[sel]
		if mode == "launch":
			for sp in engine.launch_spots(u):
				if sp[0] == h:
					aux["hex"] = h
					if not int(aux.get("dir", -1)) in sp[1]:
						aux["dir"] = sp[1][1] if sp[1].size() > 2 else sp[1][0]
					_build_decision()
					return true
			return false
		if aux.has("w"):
			var tg := []
			for tt in engine.valid_targets(int(pending["seat"])):
				if tt["hex"] == h:
					tg.append(tt)
			if not tg.is_empty():
				var i := 0
				if aux.get("t", "") != "":
					for k in tg.size():
						if tg[k]["id"] == aux["t"]:
							i = (k + 1) % tg.size()
				aux["t"] = tg[i]["id"]
				_build_decision()
				return true
	if t == "deploy":
		var cur: String = aux.get("ship", "")
		for s in pending["ships"]:
			if s["id"] == cur and h in s["allowed"]:
				for other in plan["hex"]:
					if other != cur and plan["hex"][other] == h:
						plan["hex"][other] = plan["hex"].get(cur, null)
				plan["hex"][cur] = h
				# passa alla nave successiva
				var ids := []
				for s2 in pending["ships"]:
					ids.append(s2["id"])
				var k := ids.find(cur)
				aux["ship"] = ids[(k + 1) % ids.size()]
				_build_decision()
				return true
	return false


# ---------------------------------------------------------------- fuoco

func _build_fire() -> void:
	var side := int(pending["seat"])
	_txt("Scegliete l'unità, l'arma e poi il bersaglio sulla mappa (con la probabilità di colpire). Si spara una volta per arma: il risultato arriva subito.", UI.MUTED, 16)
	var units := _fire_units(side)
	_unit_strip(units, func(u):
		if u["kind"] == "mis":
			return "MIMS"
		var n := 0
		var b: Dictionary = engine.fire_budget.get(u["id"], {})
		for k in b:
			n += int(b[k])
		return "%s · %d" % [u["label"], n])
	if sel != "" and engine.units.has(sel):
		var u: Dictionary = engine.units[sel]
		if u["kind"] == "mis" and u["cls"] == "m" and u["side"] == side and not u.get("mims_used", false):
			act_box.add_child(UI.heading("MIMS %s" % u["label"], 22, UI.SIDE[side]))
			_txt("Il MIMS può aprirsi una volta e lanciare quattro missili non guidati negli esagoni davanti a sé (puntati come suggerisce il computer di bordo).", UI.TEXT, 17)
			_btn("Apri il MIMS", func():
				var r := _mims_plan(u)
				_submit(r), true)
		elif engine.fire_budget.has(sel) and u["side"] == side:
			if not engine.fire_budget[sel].is_empty() and int(engine.fire_budget[sel].get("x", 0)) > 0:
				_txt("Comunicazioni di battaglia: un fuoco in più da una qualsiasi arma.", UI.MUTED, 16)
			for src in engine.fire_sources(u):
				var name := "Burster (classe %d)" % engine.sdef(u)["burst"] if str(src) == "burst" else "Modulo %d · %s%s" % [int(src) + 1, D.PODS[u["pods"][src]["t"]]["name"], " (danneggiato)" if engine.pod_state(u, src) == 2 else ""]
				if str(src) == "burst":
					act_box.add_child(UI.label(name, 18, UI.YELLOW, UI.font_semi))
				else:
					var hr := HBoxContainer.new()
					hr.add_theme_constant_override("separation", 8)
					hr.add_child(UI.icon_rect(UI.tex(D.pod_img(u["pods"][src]["t"])), Vector2(70, 28)))
					hr.add_child(UI.label(name, 18, UI.YELLOW, UI.font_semi))
					act_box.add_child(hr)
				var g := HFlowContainer.new()
				g.add_theme_constant_override("h_separation", 6)
				g.add_theme_constant_override("v_separation", 6)
				act_box.add_child(g)
				for w in engine.weapons_of(u, src):
					var cost := engine.fire_cost(u, w)
					var ww: String = w
					var ss = src
					var b := UI.button("%s%s" % [D.FIRE[w]["name"], (" (%d u.)" % cost) if cost > 0 else ""], 0, 40, 16)
					b.disabled = engine.energy(u) < cost
					if aux.get("w", "") == w and str(aux.get("src", "")) == str(src):
						UI.primary(b)
					b.pressed.connect(func():
						mode = ""
						aux = {"src": ss, "w": ww, "t": aux.get("t", "")}
						_rebuild())
					g.add_child(b)
			var lo := engine.launchable(u)
			if not lo.is_empty():
				act_box.add_child(UI.label("Lancio di missili", 18, UI.PINK, UI.font_semi))
				var g2 := HFlowContainer.new()
				g2.add_theme_constant_override("h_separation", 6)
				g2.add_theme_constant_override("v_separation", 6)
				act_box.add_child(g2)
				for o in lo:
					var oo: Dictionary = o
					var b := UI.button("%s · mod. %d%s" % [D.MNAME[o["mt"]], int(o["pod"]) + 1, " (pronto)" if o["mis"] != "" else ""], 0, 40, 16)
					if mode == "launch" and int(aux.get("pod", -1)) == int(o["pod"]) and aux.get("mt", "") == o["mt"]:
						UI.primary(b)
					b.pressed.connect(func():
						mode = "launch"
						aux = {"pod": oo["pod"], "mt": oo["mt"], "v": clampi(int(u["v"]) + 1, 1, 9)}
						_rebuild())
					g2.add_child(b)
			if aux.has("w") and mode == "":
				_fire_target_box(u)
			if mode == "launch":
				_launch_box(u)
	var r := _foot_row()
	_btn("Suggerisci (IA)", func():
		var s = engine.ais[side].decide(engine, side, pending)
		if s is Dictionary and not s.is_empty():
			if s.has("mims"):
				sel = s["mims"]
				aux = {}
			elif s.has("launch"):
				sel = s["s"]
				mode = "launch"
				aux = {"pod": s["src"], "mt": s["launch"], "hex": s["hex"], "dir": s["dir"], "v": s["v"]}
			else:
				sel = s["s"]
				mode = ""
				aux = {"src": s["src"], "w": s["w"], "t": s["t"]}
			_card()
		else:
			status_lbl.text = "L'IA non sparerebbe altro."
		_rebuild(), false, 0, r)
	_btn("Fine fuoco", func(): _submit({}), true, 0, r)


func _fire_target_box(u: Dictionary) -> void:
	var tid: String = aux.get("t", "")
	if tid == "" or not engine.units.has(tid) or engine.units[tid]["st"] != "on":
		_txt("Ora tocca un bersaglio sulla mappa (cerchi rossi).", UI.YELLOW, 17)
		return
	var t: Dictionary = engine.units[tid]
	var tv := engine.target_value(u, aux["src"], t)
	var ch := engine.hit_chance(aux["w"], tv["tv"])
	var info := "Bersaglio: %s\nGittata %d%s · velocità relativa %d · puntamento %d = valore %d" % [
		engine.uname_for(t, u["side"]), tv["range"], "" if tv["range"] == Hex.dist(u["hex"], t["hex"]) else " (dimezzata)", tv["rv"], tv["mod"], tv["tv"]]
	_txt(info, UI.TEXT, 17)
	var txt := "colpo impossibile" if ch <= 0 else ("colpo automatico" if ch >= 99 else "serve %d o meno sul d10 (%d%%)" % [ch, ch * 10])
	_txt(txt, UI.YELLOW, 19, UI.font_bold)
	var b := _btn("FUOCO!", func():
		_last_fire = {"sel": u["id"], "src": aux["src"], "w": aux["w"]}
		_submit({"s": u["id"], "src": aux["src"], "w": aux["w"], "t": tid}), true)
	b.disabled = ch <= 0


func _launch_box(u: Dictionary) -> void:
	_txt("Tocca uno degli esagoni azzurri davanti alla nave, poi scegli direzione e velocità (quella della nave ±1, minimo 1).", UI.YELLOW, 16)
	if not aux.has("hex"):
		return
	var dirs := []
	for sp in engine.launch_spots(u):
		if sp[0] == aux["hex"]:
			dirs = sp[1]
	var r := _row()
	r.add_child(UI.label("Direzione", 18))
	for d in dirs:
		var dd: int = d
		_btn(D.DIR_NAMES[d], func():
			aux["dir"] = dd
			_rebuild(), int(aux.get("dir", -1)) == d, 50, r)
	var r2 := _row()
	r2.add_child(UI.label("Velocità", 18))
	for v in engine.launch_vels(u):
		var vv: int = v
		_btn(str(v), func():
			aux["v"] = vv
			_rebuild(), int(aux.get("v", -1)) == v, 50, r2)
	if not int(aux.get("v", -1)) in engine.launch_vels(u):
		aux["v"] = engine.launch_vels(u)[0]
	_btn("LANCIA!", func():
		_submit({"s": u["id"], "src": aux["pod"], "launch": aux["mt"], "hex": aux["hex"], "dir": aux["dir"], "v": aux["v"]}), true)


func _mims_plan(m: Dictionary) -> Dictionary:
	var ai: DVAI = engine.ais[m["side"]]
	var r := ai._best_mims(engine, m)
	if not r.is_empty():
		return r["ord"]
	var pl := []
	var spots := engine.launch_spots(m)
	for i in 4:
		var sp: Array = spots[i % spots.size()]
		pl.append([sp[0], sp[1][mini(1, sp[1].size() - 1)], engine.launch_vels(m)[0]])
	return {"mims": m["id"], "pl": pl}


# ---------------------------------------------------------------- schieramento, pianeti, colpi

func _build_deploy() -> void:
	_txt("Schierate le navi: scegliete la nave, poi toccate un esagono azzurro. Dove indicato, scegliete anche direzione e velocità.", UI.MUTED, 16)
	var group: bool = pending.get("group", false)
	for s in pending["ships"]:
		var u: Dictionary = engine.units[s["id"]]
		var r := _row()
		var id: String = s["id"]
		var b := _btn("%s %s" % [engine.uname(u), engine.hcode(plan["hex"][id]) if plan["hex"].get(id, null) != null else "—"], func():
			aux["ship"] = id
			_rebuild(), aux.get("ship", "") == id, 0, r)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if s["dir_free"] and not group:
			_btn("Sx", func():
				plan["dir"][id] = posmod(int(plan["dir"][id]) - 1, 12)
				_rebuild(), false, 44, r)
			r.add_child(UI.label("ore %s" % D.DIR_NAMES[plan["dir"][id]], 18, UI.YELLOW))
			_btn("Dx", func():
				plan["dir"][id] = posmod(int(plan["dir"][id]) + 1, 12)
				_rebuild(), false, 44, r)
	if group:
		var first: String = pending["ships"][0]["id"]
		var r := _row()
		r.add_child(UI.label("Direzione di tutte", 18))
		_btn("Sx", func():
			for s in pending["ships"]:
				plan["dir"][s["id"]] = posmod(int(plan["dir"][first]) - 1, 12)
			_rebuild(), false, 44, r)
		r.add_child(UI.label("ore %s" % D.DIR_NAMES[plan["dir"][first]], 20, UI.YELLOW, UI.font_bold))
		_btn("Dx", func():
			for s in pending["ships"]:
				plan["dir"][s["id"]] = posmod(int(plan["dir"][first]) + 1, 12)
			_rebuild(), false, 44, r)
	var vr: Array = pending.get("vrange", [])
	if not vr.is_empty():
		var r := _row()
		r.add_child(UI.label("Velocità (%d-%d)" % [vr[0], vr[1]], 18))
		_btn("−", func():
			plan["v"] = maxi(int(vr[0]), int(plan["v"]) - 1)
			_rebuild(), false, 44, r)
		r.add_child(UI.label(str(plan["v"]), 22, UI.YELLOW, UI.font_bold))
		_btn("+", func():
			plan["v"] = mini(int(vr[1]), int(plan["v"]) + 1)
			_rebuild(), false, 44, r)
	_btn("Conferma lo schieramento", func():
		_submit({"hex": plan["hex"], "dir": plan["dir"], "v": plan["v"]}), true, 0, _foot_row())


func _build_planet() -> void:
	var u: Dictionary = engine.units[pending["u"]]
	var lim: Dictionary = pending["lim"]
	_txt("%s entra nell'esagono del pianeta: può ricevere subito manovre gratuite (al massimo %d, velocità ±%d, non sotto 1). La parte di movimento già fatta si sottrae dalla nuova velocità: con velocità 1 resta in orbita." % [engine.uname(u), lim["n"], lim["vr"]], UI.TEXT, 17)
	var a := int(plan["a"])
	var t := int(plan["t"])
	var used := absi(a) + absi(t)
	var r := _row()
	r.add_child(UI.label("Velocità", 18))
	_btn("−", func():
		if absi(a - 1) + absi(t) <= int(lim["n"]) and a - 1 >= -int(lim["vr"]) and int(u["v"]) + a - 1 >= 1:
			plan["a"] = a - 1
		_rebuild(), false, 50, r)
	r.add_child(UI.label("da %d a %d" % [u["v"], clampi(int(u["v"]) + a, 1, 9)], 22, UI.YELLOW, UI.font_bold))
	_btn("+", func():
		if absi(a + 1) + absi(t) <= int(lim["n"]) and a + 1 <= int(lim["vr"]):
			plan["a"] = a + 1
		_rebuild(), false, 50, r)
	if not lim["single"]:
		var r2 := _row()
		r2.add_child(UI.label("Direzione", 18))
		_btn("Sx", func():
			if absi(a) + absi(t - 1) <= int(lim["n"]):
				plan["t"] = t - 1
			_rebuild(), false, 50, r2)
		r2.add_child(UI.label("ore %s" % D.DIR_NAMES[posmod(int(u["dir"]) + t, 12)], 22, UI.YELLOW, UI.font_bold))
		_btn("Dx", func():
			if absi(a) + absi(t + 1) <= int(lim["n"]):
				plan["t"] = t + 1
			_rebuild(), false, 50, r2)
	_txt("Comandi usati: %d su %d" % [used, lim["n"]], UI.CYAN)
	_btn("Conferma", func(): _submit({"a": plan["a"], "t": plan["t"]}), true, 0, _foot_row())


func _build_hitpart() -> void:
	var t: Dictionary = engine.units[pending["u"]]
	var mine: bool = t["side"] == int(pending["seat"])
	_txt("%s: il dado (%d) indica più parti. Scegliete quale viene colpita%s." % [engine.uname(t), pending["roll"], " (è una vostra unità: scegliete la meno grave)" if mine else ""], UI.TEXT, 17)
	for p in pending["options"]:
		var st := engine.part_state(t, p)
		var pp: String = p
		var b := _btn("%s  [%s]" % [engine.part_name(t, p).capitalize(), ["intatto", "vulnerabile", "danneggiato", "distrutto"][st]], func(): _submit(pp))
		if p.begins_with("p"):
			b.icon = UI.tex(D.pod_img(t["pods"][int(p.substr(1)) - 1]["t"]))
			b.expand_icon = true
			b.custom_minimum_size.y = 52
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT


# ================================================================ fine partita e replay

func _on_end(res: Dictionary) -> void:
	pending = {}
	_clear_box()
	ended = true
	status_lbl.text = ""
	if online != null:
		online.finish()
	if engine.abort:
		return
	if online == null and main != null and not config.get("tutorial", false):
		main.delete_save()
	_refresh()
	_end_panel(res)
	if tutor != null:
		move_child(tutor, -1)
		tutor.event("end")


var end_panel: Control

func _end_panel(res: Dictionary) -> void:
	end_panel = ColorRect.new()
	end_panel.color = Color(0, 0, 0, 0.72)
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(end_panel)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.dark_style(10, 0.98))
	pc.custom_minimum_size = Vector2(980, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var w := int(res.get("winner", -1))
	var t := UI.title("Pareggio" if w < 0 else "Vince %s" % engine.pname(w), 56, UI.YELLOW if w < 0 else UI.SIDE[w])
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 940
	vb.add_child(t)
	var r0 := UI.label(str(res.get("reason", "")).capitalize() if false else str(res.get("reason", "")), 26, UI.TEXT, UI.font_semi)
	r0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(UI.wrap(r0, 940))
	var info := "Turni giocati: %d" % engine.turn
	if engine.scn == 4:
		info += "   ·   Punti: convoglio %d, insorti %d" % [engine.vp[0], engine.vp[1]]
	var il := UI.label(info, 22, UI.CYAN, UI.font_mono)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(il)
	_stats_box(vb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var rp := UI.primary(UI.button("Rivedi tutta la partita", 330, 60, 24))
	rp.pressed.connect(func():
		end_panel.queue_free()
		start_replay())
	row.add_child(rp)
	var stay := UI.button("Guarda la mappa", 240, 60, 22)
	stay.pressed.connect(func(): end_panel.queue_free())
	row.add_child(stay)
	var menu := UI.button("Torna al menu", 240, 60, 22)
	menu.pressed.connect(func(): main.show_menu())
	row.add_child(menu)
	vb.add_child(row)


const STAT_ROWS := [
	["Colpi sparati", "fires"], ["Colpi a segno", "hits"], ["Colpi critici", "crit"],
	["Parti nemiche danneggiate", "dmg"], ["Missili lanciati", "launched"],
	["Intercettazioni riuscite", "mhits"], ["Missili nemici abbattuti", "mdown"],
	["Unità nemiche distrutte", "kills"], ["Unità perdute", "lost"],
	["Energia spesa (unità)", "eu"], ["Esagoni percorsi", "dist"],
]


## statistiche della partita: un confronto a barre fra i due lati e le unità migliori
func _stats_box(vb: VBoxContainer) -> void:
	vb.add_child(HSeparator.new())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(head)
	for s in 2:
		var l := UI.label(engine.pname(s), 24, UI.SIDE[s], UI.font_bold)
		l.custom_minimum_size.x = 348
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if s == 0 else HORIZONTAL_ALIGNMENT_LEFT
		l.clip_text = true
		head.add_child(l)
		if s == 0:
			var mid := UI.label("contro", 18, UI.MUTED, UI.font_semi)
			mid.custom_minimum_size.x = 250
			mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			head.add_child(mid)
	var st: Array = engine.stats
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	vb.add_child(grid)
	for rw in STAT_ROWS:
		var k: String = rw[1]
		var a := int(st[0].get(k, 0))
		var b := int(st[1].get(k, 0))
		if a == 0 and b == 0 and not k in ["fires", "hits"]:
			continue
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		grid.add_child(r)
		var mx := float(maxi(1, maxi(a, b)))
		for s in 2:
			var v := a if s == 0 else b
			var txt := str(v)
			if k == "hits" and int(st[s]["fires"]) > 0:
				txt = "%d (%d%%)" % [v, roundi(100.0 * v / int(st[s]["fires"]))]
			var vl := UI.label(txt, 19, UI.TEXT, UI.font_mono)
			vl.custom_minimum_size.x = 140
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if s == 0 else HORIZONTAL_ALIGNMENT_LEFT
			var bar := Control.new()
			bar.custom_minimum_size = Vector2(200, 26)
			var fill := ColorRect.new()
			fill.color = Color(UI.SIDE[s], 0.85)
			var wpx := 200.0 * v / mx
			fill.size = Vector2(wpx, 16)
			fill.position = Vector2(200.0 - wpx if s == 0 else 0.0, 5)
			bar.add_child(fill)
			if s == 0:
				r.add_child(vl)
				r.add_child(bar)
				var nl := UI.label(rw[0], 18, UI.CYAN, UI.font_semi)
				nl.custom_minimum_size.x = 250
				nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				r.add_child(nl)
			else:
				r.add_child(bar)
				r.add_child(vl)
	# le unità migliori
	var best := ["", ""]
	var bscore := [0, 0]
	for id in engine.ustats:
		var us: Dictionary = engine.ustats[id]
		var sd := int(engine.reg[id]["side"])
		var sc := int(us["dmg"]) * 2 + int(us["kills"]) * 6 + int(us["hits"])
		if sc > bscore[sd]:
			bscore[sd] = sc
			best[sd] = id
	var bl := HBoxContainer.new()
	bl.add_theme_constant_override("separation", 20)
	bl.alignment = BoxContainer.ALIGNMENT_CENTER
	for s in 2:
		if best[s] == "":
			continue
		var us: Dictionary = engine.ustats[best[s]]
		var u: Dictionary = engine.units[best[s]]
		var t := "Migliore: %s, %d colpi a segno su %d, %d parti danneggiate%s" % [engine.uname(u), us["hits"], us["fires"], us["dmg"],
			(", %d unità distrutte" % us["kills"]) if int(us["kills"]) > 1 else (", 1 unità distrutta" if int(us["kills"]) == 1 else "")]
		var l := UI.label(t, 17, UI.SIDE[s], UI.font_semi)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 450
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if s == 0 else HORIZONTAL_ALIGNMENT_LEFT
		bl.add_child(l)
	if bl.get_child_count() > 0:
		vb.add_child(bl)
	vb.add_child(HSeparator.new())


func start_replay() -> void:
	replaying = true
	rp_track = ReplayTrack.new()
	rp_track.build(engine.history, engine.reg)
	rp_starts = [0.0, rp_track.total]
	rp_time = 0.0
	_set_state(rp_track.state_at(0.0))
	board2d.fit(true)
	board3d.fit(true)
	if rp_follow:
		board2d.zoom = maxf(board2d.zoom, 0.5)
		board2d.world.scale = Vector2(board2d.zoom, board2d.zoom)
		board3d.dist = minf(board3d.dist, 30.0)
		board3d._update_cam()
	rp_play = true
	sel = ""
	_card()
	_clear_box()
	act_box.add_child(UI.title("Replay", 34))
	_txt("La partita intera come un film continuo: in ogni turno tutte le unità dei due lati si muovono insieme, ciascuna alla sua velocità, mentre laser, particelle e missili partono in tempo reale dalle navi in movimento. Si può fermare, accelerare e spostare con il cursore; la mappa resta girevole (2D o 3D). Tutte le pedine sono scoperte.", UI.MUTED, 17)
	_btn("Esci dal replay", func(): stop_replay())
	if is_instance_valid(replay_bar):
		replay_bar.queue_free()
	replay_bar = PanelContainer.new()
	replay_bar.add_theme_stylebox_override("panel", UI.dark_style(6, 0.95))
	replay_bar.anchor_left = 0.0
	replay_bar.anchor_right = 1.0
	replay_bar.anchor_top = 1.0
	replay_bar.anchor_bottom = 1.0
	replay_bar.offset_left = 20
	replay_bar.offset_right = -20
	replay_bar.offset_top = -230
	replay_bar.offset_bottom = -164
	board_area.add_child(replay_bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	replay_bar.add_child(hb)
	var rw := UI.button("«", 54, 44, 20)
	rw.pressed.connect(func(): rp_time = 0.0)
	hb.add_child(rw)
	rp_btn = UI.button("Pausa", 90, 44, 18)
	rp_btn.pressed.connect(func():
		rp_play = not rp_play
		if rp_play and rp_time >= rp_starts[-1]:
			rp_time = 0.0
		rp_btn.text = "Pausa" if rp_play else "Avvia")
	hb.add_child(rp_btn)
	for sp in [0.5, 1.0, 2.0, 4.0]:
		var s: float = sp
		var b := UI.button("%s×" % ("½" if sp == 0.5 else str(int(sp))), 54, 44, 18)
		b.pressed.connect(func(): rp_speed = s)
		hb.add_child(b)
	var fb := UI.button("Segui l'azione", 150, 44, 17)
	fb.toggle_mode = true
	fb.button_pressed = rp_follow
	fb.toggled.connect(func(on): rp_follow = on)
	hb.add_child(fb)
	rp_slider = HSlider.new()
	rp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rp_slider.min_value = 0.0
	rp_slider.max_value = maxf(0.1, rp_starts[-1])
	rp_slider.step = 0.01
	rp_slider.drag_started.connect(func(): _rp_drag = true)
	rp_slider.drag_ended.connect(func(_c): _rp_drag = false)
	rp_slider.value_changed.connect(func(v):
		if _rp_drag:
			rp_time = v)
	hb.add_child(rp_slider)
	rp_lbl = UI.label("", 18, UI.YELLOW, UI.font_mono)
	rp_lbl.custom_minimum_size.x = 260
	hb.add_child(rp_lbl)


func _replay_sounds(a: float, b: float) -> void:
	if b <= a or b - a > 0.5:
		return
	for f in rp_track.fx:
		var t0: float = f["t0"]
		if t0 <= a or t0 > b:
			continue
		match f["k"]:
			"beam":
				var w := str(f["w"])
				main.sfx(WSND.get(w, "laser"), -5.0)
				var pt: Array = FX2D.pattern(w)
				var arrive: float = (float(pt[1]) * (int(pt[0]) - 1) + float(pt[2])) * float(f["dur"])
				main.sfx("impatto" if f["hit"] else "mancato", -4.0, arrive / maxf(0.25, rp_speed))
			"boom":
				main.sfx("esplosione", -1.0)
			"puff":
				main.sfx("missile", -5.0)
			"warp":
				main.sfx("salto", -3.0)
			"text":
				if str(f["txt"]) == "INTERCETTATO!":
					main.sfx("intercetta", -6.0)
	# motori all'inizio del movimento di ogni turno
	var ta := (a - ReplayTrack.START) / ReplayTrack.TT
	var tb := (b - ReplayTrack.START) / ReplayTrack.TT
	if tb > 0 and floorf(ta - 0.05) != floorf(tb - 0.05):
		main.sfx("motori", -10.0)


func stop_replay() -> void:
	replaying = false
	if is_instance_valid(replay_bar):
		replay_bar.queue_free()
	_clear_box()
	live_dirty = true
	_end_panel(engine.result)


func _replay_step(dt: float) -> void:
	if rp_track == null:
		return
	var total: float = rp_track.total
	if rp_play and not _rp_drag:
		rp_time = minf(total, rp_time + dt * rp_speed)
		if rp_time >= total:
			rp_play = false
			if is_instance_valid(rp_btn):
				rp_btn.text = "Avvia"
	if rp_play and not _rp_drag:
		_replay_sounds(_rp_last, rp_time)
	_rp_last = rp_time
	var st := rp_track.state_at(rp_time)
	var b = board3d if view3d else board2d
	b.viewer = [0, 1]
	b.ov = {}
	b.set_state(st)
	if rp_follow:
		_follow(st, dt)
	if is_instance_valid(rp_slider) and not _rp_drag:
		rp_slider.set_value_no_signal(rp_time)
	if is_instance_valid(rp_lbl):
		rp_lbl.text = rp_track.label_at(rp_time)


# ================================================================ varie

func _confirm_menu() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Tornare al menu?"
	if not ended:
		if online != null:
			dlg.dialog_text = "Tornare al menu? Potrai rientrare nella partita online con il suo codice."
		elif config.get("tutorial", false):
			dlg.dialog_text = "Uscire dal tutorial?"
		else:
			dlg.dialog_text = "Tornare al menu? La partita resta salvata: potrai riprenderla dal menu."
	dlg.ok_button_text = "Sì, al menu"
	dlg.cancel_button_text = "Annulla"
	add_child(dlg)
	dlg.confirmed.connect(func():
		engine.abort = true
		if pending.size() > 0:
			engine.provide_decision(null)
		if online != null:
			online.alive = false
		main.show_menu())
	dlg.popup_centered()


func _show_rules_popup() -> void:
	var r := preload("res://scripts/ui/rules_view.gd").new()
	r.main = main
	r.popup = true
	add_child(r)


func online_waiting(s: int, slow: bool) -> void:
	if s < 0:
		status_lbl.text = ""
	else:
		status_lbl.text = "Aspetto %s…%s" % [engine.pname(s), " (lento)" if slow else ""]


func online_status(t: String) -> void:
	status_lbl.text = t


func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_box()
	status_lbl.text = t
	_refresh()


func online_caught_up() -> void:
	status_lbl.text = "Partita ripresa."
