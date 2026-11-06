extends Control
## Menu principale: scenario, chi guida i due lati (persona o IA), opzioni e gioco online.

const D = preload("res://scripts/data/dv_data.gd")
const MODES := ["Persona", "IA facile", "IA normale", "IA difficile"]

var main
var page: Control
var scenario := 0
var modes := [0, 2]
var names := ["", ""]
var speed := 1
var anim := 1
var view3d := 0
var turns := 2
var msg: Label
var sc_box: VBoxContainer
var sc_text: RichTextLabel
var seat_rows: Array = []
var sc_btns: Array = []
var sc_ships: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = main.menu_state
	if not st.is_empty():
		scenario = st["scenario"]
		modes = st["modes"].duplicate()
		names = st["names"].duplicate()
		speed = st["speed"]
		anim = st.get("anim", 1)
		view3d = st.get("view3d", 0)
		turns = st.get("turns", 2)
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)

	# a sinistra: la scatola
	var frame := PanelContainer.new()
	var fs := UI.panel_style(Color.BLACK, UI.METAL, 3, 4)
	fs.set_content_margin_all(4)
	fs.shadow_color = Color(0, 0, 0, 0.7)
	fs.shadow_size = 18
	frame.add_theme_stylebox_override("panel", fs)
	frame.position = Vector2(70, 70)
	frame.add_child(UI.icon_rect(UI.tex("res://assets/misc/copertina.webp"), Vector2(560, 739)))
	page.add_child(frame)
	var t1 := UI.title("DeltaVee", 104)
	t1.position = Vector2(70, 830)
	page.add_child(t1)
	var t2 := UI.label("Tactical Space Combat System for UNIVERSE", 26, UI.PINK, UI.font_bold)
	t2.position = Vector2(76, 958)
	page.add_child(t2)
	var t3 := UI.label("John H. Butterfield · Simulations Publications, Inc. · 1981", 20, UI.MUTED, UI.font_semi)
	t3.position = Vector2(76, 994)
	page.add_child(t3)

	# a destra: scenario e giocatori
	var col := VBoxContainer.new()
	col.position = Vector2(700, 30)
	col.custom_minimum_size = Vector2(1160, 0)
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	col.add_child(UI.heading("Scenario", 26, UI.YELLOW))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var stars := ["Piccolo", "Sword", "Iota", "Mu", "Spear", "Clarinet"]
	for i in D.SCENARIOS.size() + 1:
		var nm: String = D.SCENARIOS[i]["name"] if i < D.SCENARIOS.size() else "Battaglia libera"
		var b := UI.button("%d · %s" % [i + 1, nm], 184, 118, 18)
		b.icon = UI.tex("res://assets/ships_alt/%s.webp" % stars[i])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.clip_text = true
		var k := i
		b.pressed.connect(func():
			scenario = k
			_refresh())
		row.add_child(b)
		sc_btns.append(b)
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", UI.dark_style(6, 0.9))
	sp.custom_minimum_size = Vector2(1160, 0)
	col.add_child(sp)
	var spv := VBoxContainer.new()
	spv.add_theme_constant_override("separation", 10)
	sp.add_child(spv)
	sc_text = RichTextLabel.new()
	sc_text.bbcode_enabled = true
	sc_text.fit_content = true
	sc_text.add_theme_font_size_override("normal_font_size", 20)
	sc_text.add_theme_font_size_override("bold_font_size", 21)
	spv.add_child(sc_text)
	sc_ships = HBoxContainer.new()
	sc_ships.add_theme_constant_override("separation", 8)
	spv.add_child(sc_ships)
	col.add_child(UI.heading("Comandanti", 26, UI.YELLOW))
	for s in 2:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		col.add_child(r)
		seat_rows.append(r)
	col.add_child(UI.heading("Opzioni", 26, UI.YELLOW))
	var o1 := HBoxContainer.new()
	o1.add_theme_constant_override("separation", 26)
	col.add_child(o1)
	o1.add_child(_segmented("Vista", ["Mappa 2D", "Tabellone 3D"], view3d, func(k): view3d = k, 150))
	o1.add_child(_segmented("Turni massimi", ["20", "30", "40", "60"], turns, func(k): turns = k, 64))
	var o2 := HBoxContainer.new()
	o2.add_theme_constant_override("separation", 26)
	col.add_child(o2)
	o2.add_child(_segmented("Pausa dell'IA", ["Lunga", "Normale", "Breve", "Nessuna"], speed, func(k): speed = k, 104))
	o2.add_child(_segmented("Animazioni", ["Lente", "Normali", "Veloci"], anim, func(k): anim = k, 100))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	col.add_child(btns)
	var play := UI.primary(UI.button("Gioca", 300, 70, 30))
	play.pressed.connect(_on_start)
	btns.add_child(play)
	var onl := UI.button("Gioca online", 240, 70, 24)
	onl.pressed.connect(_online_panel)
	btns.add_child(onl)
	var rules := UI.button("Regole", 180, 70, 24)
	rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(rules)
	var tut := UI.button("Tutorial", 180, 70, 24)
	tut.pressed.connect(_on_tutorial)
	btns.add_child(tut)
	_resume_row(col)
	msg = UI.label("", 20, UI.PINK)
	col.add_child(msg)
	_refresh()


func _center() -> void:
	var vs := get_viewport_rect().size
	var k := minf(vs.x / 1920.0, vs.y / 1080.0)
	page.scale = Vector2(k, k)
	page.position = (vs - Vector2(1920, 1080) * k) * 0.5


func _store() -> void:
	main.menu_state = {"scenario": scenario, "modes": modes.duplicate(), "names": names.duplicate(), "speed": speed,
		"anim": anim, "view3d": view3d, "turns": turns}


func _refresh() -> void:
	for i in sc_btns.size():
		var b: Button = sc_btns[i]
		if i == scenario:
			UI.primary(b)
		else:
			for k in ["normal", "hover", "pressed", "disabled"]:
				b.remove_theme_stylebox_override(k)
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				b.remove_theme_color_override(k)
			b.remove_theme_font_override("font")
	var sc: Dictionary = _sc()
	var t := "[font_size=30][color=#f4e46a]%s[/color][/font_size]   [color=#9b9384](%s)[/color]\n" % [sc["name"], sc["orig"]]
	t += sc["text"] + "\n"
	t += "[color=%s][b]%s[/b][/color]  contro  [color=%s][b]%s[/b][/color]" % [UI.SIDE[0].to_html(false), sc["sides"][0], UI.SIDE[1].to_html(false), sc["sides"][1]]
	if scenario == D.CUSTOM:
		var y: Dictionary = main.yard()
		t += "   [color=#f4e46a](punti %d contro %d)[/color]" % [D.fleet_pts(y["fleets"][0]), D.fleet_pts(y["fleets"][1])]
	t += "\n"
	t += "[color=#8fd3f4][b]Vittoria:[/b] %s[/color]" % sc["win"]
	sc_text.text = t
	# le navi dello scenario con le loro illustrazioni
	for c in sc_ships.get_children():
		c.queue_free()
	var n := 0
	for side in 2:
		for f in sc["forces"][side]:
			n += 1
	var tw := minf(220.0, (1130.0 - 8 * (n - 1)) / maxi(1, n))
	if scenario == D.CUSTOM:
		tw = minf(tw, (1130.0 - 8 * n - 190.0) / maxi(1, n))
	for side in 2:
		for f in sc["forces"][side]:
			var pc := PanelContainer.new()
			var ps := UI.panel_style(UI.NAVY, UI.SIDE[side], 2, 4)
			ps.set_content_margin_all(3)
			pc.add_theme_stylebox_override("panel", ps)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			pc.add_child(v)
			var img := TextureRect.new()
			var alt := "res://assets/ships_alt/%s.webp" % f["cls"]
			img.texture = UI.tex(alt) if ResourceLoader.exists(alt) else ShipCard.ship_img(f["cls"])
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			img.custom_minimum_size = Vector2(tw - 6, (tw - 6) * 0.36)
			img.clip_contents = true
			v.add_child(img)
			var l := UI.label("%s %s" % [D.SHIPS[f["cls"]]["name"], f["id"]], 16, UI.SIDE[side], UI.font_bold)
			l.clip_text = true
			l.custom_minimum_size.x = tw - 8
			v.add_child(l)
			sc_ships.add_child(pc)
	if scenario == D.CUSTOM:
		var yb := UI.primary(UI.button("Cantiere navale", 180, 72, 20))
		yb.pressed.connect(func():
			_store()
			main.show_shipyard())
		sc_ships.add_child(yb)
	for s in 2:
		var r: HBoxContainer = seat_rows[s]
		for c in r.get_children():
			c.queue_free()
		var lab := UI.label("%s · %s" % [D.SIDE_NAMES[s], sc["sides"][s]], 21, UI.SIDE[s], UI.font_bold)
		lab.custom_minimum_size.x = 380
		lab.clip_text = true
		r.add_child(lab)
		var k := s
		r.add_child(_segmented("", MODES, modes[s], func(m): modes[k] = m, 118))
		var le := _line("Nome (facoltativo)", 18)
		le.text = names[s]
		le.custom_minimum_size = Vector2(220, 48)
		le.text_changed.connect(func(tx): names[k] = tx)
		r.add_child(le)


func _segmented(label_text: String, items: Array, cur: int, cb: Callable, w := 120) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	if label_text != "":
		var l := UI.label(label_text, 20, UI.TEXT, UI.font_semi)
		l.custom_minimum_size.x = 0
		h.add_child(l)
		var spc := Control.new()
		spc.custom_minimum_size.x = 6
		h.add_child(spc)
	var btns := []
	for i in items.size():
		var b := UI.button(items[i], w, 46, 18)
		b.toggle_mode = true
		b.button_pressed = i == cur
		btns.append(b)
		h.add_child(b)
	for i in btns.size():
		var k := i
		btns[i].pressed.connect(func():
			for j in btns.size():
				btns[j].button_pressed = j == k
			cb.call(k))
	return h


## scenario scelto (la battaglia libera si costruisce dai dati del cantiere)
func _sc() -> Dictionary:
	if scenario == D.CUSTOM:
		return D.custom_scenario(main.yard())
	return D.SCENARIOS[scenario]


func _config() -> Dictionary:
	var seats := []
	var sc: Dictionary = _sc()
	for s in 2:
		var nm: String = names[s].strip_edges()
		if nm == "":
			nm = sc["sides"][s]
		seats.append({"name": nm, "ai": modes[s] != 0, "level": maxi(0, modes[s] - 1)})
	var delays := [1.4, 0.7, 0.25, 0.0]
	var anims := [0.6, 1.0, 1.8]
	var cfg := {"scenario": scenario, "seats": seats, "ai_delay": delays[speed], "anim": anims[anim],
		"view3d": view3d == 1, "max_turns": [20, 30, 40, 60][turns]}
	if scenario == D.CUSTOM:
		cfg["custom"] = sc
	return cfg


## partita salvata: si riprende da dove era rimasta
func _resume_row(col: VBoxContainer) -> void:
	var d: Dictionary = main.saved_game()
	if d.is_empty():
		return
	var pc := PanelContainer.new()
	var st := UI.panel_style(Color(0.05, 0.08, 0.18, 0.95), UI.YELLOW, 2, 6)
	st.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", st)
	pc.custom_minimum_size = Vector2(1160, 0)
	col.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	var cfg: Dictionary = d["cfg"]
	var scn := clampi(int(d.get("scn", cfg.get("scenario", 0))), 0, D.CUSTOM)
	var who := []
	for s in cfg.get("seats", []):
		who.append(("IA %s" % ["facile", "normale", "difficile"][clampi(int(s.get("level", 1)), 0, 2)]) if s.get("ai", false) else str(s.get("name", "")))
	var when := str(d.get("when", "")).replace("T", " ")
	if when.length() >= 16:
		when = "%s/%s alle %s" % [when.substr(8, 2), when.substr(5, 2), when.substr(11, 5)]
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	info.add_child(UI.label("Partita in sospeso", 22, UI.YELLOW, UI.font_bold))
	var l := UI.label("%d · %s, turno %d · %s · salvata il %s" % [scn + 1, "Battaglia libera" if scn == D.CUSTOM else D.SCENARIOS[scn]["name"], maxi(1, int(d.get("turn", 1))), " contro ".join(who), when], 18, UI.TEXT, UI.font_semi)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(l)
	var go := UI.primary(UI.button("Riprendi", 180, 56, 22))
	go.pressed.connect(func():
		_store()
		main.resume_game())
	hb.add_child(go)
	var del := UI.button("Elimina", 130, 56, 20)
	del.pressed.connect(func():
		main.delete_save()
		pc.queue_free())
	hb.add_child(del)


func _on_tutorial() -> void:
	_store()
	main.start_game({"scenario": 0, "tutorial": true, "max_turns": 30, "ai_delay": 1.0, "anim": 0.8, "view3d": false,
		"seats": [{"name": "I tagliagole", "ai": false, "level": 0}, {"name": "La guardia locale", "ai": true, "level": 0}]})


func _on_start() -> void:
	_store()
	main.start_game(_config())


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button
var host_side := 0


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.dark_style(10, 0.98))
	box.position = page.position + Vector2(560, 120) * page.scale
	box.scale = page.scale
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 52))
	var info := UI.label("Chi crea la stanza sceglie qui quale lato gioca; l'amico entra con il codice. Scenario e opzioni scelti nel menu valgono per tutti.", 20, UI.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var sc: Dictionary = _sc()
	vb.add_child(_segmented("Tu giochi", [sc["sides"][0], sc["sides"][1]], host_side, func(k): host_side = k, 300))
	var b_create := UI.button("Crea una stanza", 0, 56, 22)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.button("Entra", 200, 56, 22)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 21, Color.WHITE)
	on_lbl.custom_minimum_size = Vector2(760, 110)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = UI.primary(UI.button("Inizia online", 420, 60, 24))
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := UI.button("Indietro", 300, 60, 22)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _seat_names() -> Array:
	var sc: Dictionary = _sc()
	return [sc["sides"][0], sc["sides"][1]]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 56)
	le.add_theme_font_size_override("font_size", 24)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parts.append("%s: %s" % [_seat_names()[int(idx)], who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := [host_side, 1 - host_side]
	modes = [0, 0]
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice al tuo amico.\nPosti: %s.\nQuando c'è premi Inizia online (un posto rimasto libero lo gioca l'IA)." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (giochi: %s).\nAspetta che chi l'ha creata avvii la partita." % [code, _seat_names()[int(main.lobby["seat"])]])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: scenario, giocatori e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	modes = [0, 0]
	var cfg := _config()
	for i in 2:
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary:
			cfg["seats"][i]["name"] = str(seats_db[k].get("name", cfg["seats"][i]["name"]))
			cfg["seats"][i]["ai"] = false
		else:
			cfg["seats"][i]["ai"] = true
			cfg["seats"][i]["level"] = 1
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	# la vista resta quella scelta su questo dispositivo
	cfg["view3d"] = view3d == 1
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
