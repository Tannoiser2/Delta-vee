extends Control
## Cantiere navale: si costruiscono le due flotte della battaglia libera (classi, moduli, corazze,
## caccia), con i punti per bilanciarle, il terreno, la distanza e la velocità di partenza.
## Il regolamento non prevede la costruzione delle flotte: i punti sono un aiuto (vedi D.hull_pts / D.pod_pts).

const D = preload("res://scripts/data/dv_data.gd")
const CLASSES := ["TX", "T5000", "Piccolo", "Dagger", "Gamma", "Flute", "Sword", "Zeta", "Clarinet", "Spear", "Iota", "Mu"]

var main
var page: Control
var y: Dictionary
var cols: Array = []            # VBox delle due flotte
var pts_lbl: Array = []
var edit_box: Control           # finestra di modifica di una nave
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rng.randomize()
	y = main.yard()
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)
	_build()


func _center() -> void:
	var vs := get_viewport_rect().size
	var k := minf(vs.x / 1920.0, vs.y / 1080.0)
	page.scale = Vector2(k, k)
	page.position = (vs - Vector2(1920, 1080) * k) * 0.5


func _save() -> void:
	main.save_yard()


# ================================================================ pagina

func _build() -> void:
	for c in page.get_children():
		c.queue_free()
	cols = []
	pts_lbl = []
	var t := UI.title("Cantiere navale", 64)
	t.position = Vector2(40, 18)
	page.add_child(t)
	var sub := UI.label("Costruite le due flotte della battaglia libera: classi, moduli, corazze e caccia. I punti aiutano a bilanciarle (il regolamento non prevede la costruzione delle flotte).", 19, UI.MUTED, UI.font_semi)
	sub.position = Vector2(44, 100)
	sub.custom_minimum_size.x = 1300
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(sub)
	var back := UI.button("Torna al menu", 220, 60, 22)
	back.position = Vector2(1410, 26)
	back.pressed.connect(_done)
	page.add_child(back)
	var go := UI.primary(UI.button("Gioca", 220, 60, 26))
	go.position = Vector2(1660, 26)
	go.pressed.connect(_done)
	page.add_child(go)
	# opzioni
	var o := HBoxContainer.new()
	o.position = Vector2(40, 150)
	o.add_theme_constant_override("separation", 30)
	page.add_child(o)
	o.add_child(_segmented("Terreno", ["Spazio aperto", "Pianeta", "Asteroidi"], int(y.get("terrain", 0)), func(k):
		y["terrain"] = k
		_save(), 150))
	o.add_child(_segmented("Distanza", ["Vicina", "Media", "Lontana"], int(y.get("dist", 1)), func(k):
		y["dist"] = k
		_save(), 100))
	var o2 := HBoxContainer.new()
	o2.position = Vector2(40, 212)
	o2.add_theme_constant_override("separation", 30)
	page.add_child(o2)
	o2.add_child(_segmented("Velocità di partenza", ["0", "1", "2", "3", "4"], int(y.get("v", 2)), func(k):
		y["v"] = k
		_save(), 56))
	o2.add_child(_segmented("Punti per flotta", ["Liberi", "100", "200", "300"], int(y.get("budget", 2)), func(k):
		y["budget"] = k
		_save()
		_refresh_pts(), 96))
	# le due flotte
	for side in 2:
		var pc := PanelContainer.new()
		var ps := UI.panel_style(Color(0.03, 0.05, 0.12, 0.92), UI.SIDE[side], 2, 6)
		ps.set_content_margin_all(12)
		pc.add_theme_stylebox_override("panel", ps)
		pc.position = Vector2(40 + side * 930, 280)
		pc.custom_minimum_size = Vector2(910, 780)
		pc.size = Vector2(910, 780)
		page.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		pc.add_child(v)
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 10)
		v.add_child(hr)
		var le := LineEdit.new()
		le.text = str(y["sides"][side])
		le.custom_minimum_size = Vector2(380, 50)
		le.add_theme_font_override("font", UI.font_bold)
		le.add_theme_font_size_override("font_size", 24)
		le.add_theme_color_override("font_color", UI.SIDE[side])
		for stn in ["normal", "focus", "read_only"]:
			var ls := UI.panel_style(Color("#0b1124"), UI.SIDE[side] if stn == "focus" else Color("#2b3654"), 2, 4)
			ls.content_margin_left = 12
			le.add_theme_stylebox_override(stn, ls)
		var k := side
		le.text_changed.connect(func(tx):
			y["sides"][k] = tx if tx.strip_edges() != "" else ("Flotta arancione" if k == 0 else "Flotta verde")
			_save())
		hr.add_child(le)
		var pl := UI.label("", 24, UI.YELLOW, UI.font_bold)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hr.add_child(pl)
		pts_lbl.append(pl)
		var ar := HBoxContainer.new()
		ar.add_theme_constant_override("separation", 8)
		v.add_child(ar)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(380, 46)
		ob.add_theme_font_size_override("font_size", 18)
		for cls in CLASSES:
			ob.add_item("%s · %d moduli · %d punti" % [D.SHIPS[cls]["name"], D.SHIPS[cls]["pods"], D.ship_pts({"cls": cls, "pods": D.default_pods(cls)})])
		ob.selected = 6
		ar.add_child(ob)
		var add := UI.button("Aggiungi", 140, 46, 18)
		add.pressed.connect(func(): _add(k, CLASSES[ob.selected]))
		ar.add_child(add)
		var rnd := UI.button("Casuale", 120, 46, 18)
		rnd.tooltip_text = "Una flotta a caso entro i punti scelti"
		rnd.pressed.connect(func(): _random(k))
		ar.add_child(rnd)
		var clr := UI.button("Svuota", 110, 46, 18)
		clr.pressed.connect(func():
			y["fleets"][k] = []
			_save()
			_fill(k))
		ar.add_child(clr)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 6)
		v.add_child(list)
		cols.append(list)
	for side in 2:
		_fill(side)


func _done() -> void:
	_save()
	var st: Dictionary = main.menu_state
	st["scenario"] = D.CUSTOM
	if not st.has("modes"):
		st.merge({"modes": [0, 2], "names": ["", ""], "speed": 1, "anim": 1, "view3d": 0, "turns": 2})
	main.menu_state = st
	main.show_menu()


func _refresh_pts() -> void:
	var b: int = D.YARD_BUDGETS[clampi(int(y.get("budget", 2)), 0, 3)]
	for side in 2:
		var p := D.fleet_pts(y["fleets"][side])
		var l: Label = pts_lbl[side]
		l.text = ("Punti %d" % p) if b == 0 else ("Punti %d su %d" % [p, b])
		l.add_theme_color_override("font_color", UI.RED if b > 0 and p > b else UI.YELLOW)


func _fill(side: int) -> void:
	var list: VBoxContainer = cols[side]
	for c in list.get_children():
		c.queue_free()
	var fl: Array = y["fleets"][side]
	for i in fl.size():
		list.add_child(_ship_row(side, i))
	if fl.is_empty():
		list.add_child(UI.label("Nessuna astronave: sceglietene una e premete Aggiungi.", 18, UI.MUTED, UI.font_semi))
	elif fl.size() >= D.YARD_MAX:
		list.add_child(UI.label("Al massimo %d astronavi per flotta." % D.YARD_MAX, 16, UI.MUTED, UI.font_semi))
	_refresh_pts()


func _ship_row(side: int, i: int) -> Control:
	var f: Dictionary = y["fleets"][side][i]
	var cls: String = f["cls"]
	var pc := PanelContainer.new()
	var ps := UI.panel_style(Color("#131c36"), Color("#2b3654"), 1, 4)
	ps.set_content_margin_all(6)
	pc.add_theme_stylebox_override("panel", ps)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	h.add_child(_fit_img(ShipCard.ship_img(cls), Vector2(160, 62)))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	mid.add_child(UI.label("%s %s" % [D.SHIPS[cls]["name"], "ABCDEF"[i]], 21, UI.SIDE[side], UI.font_bold))
	var names := []
	for pd in f["pods"]:
		names.append(D.PODS[pd[0]]["short"])
	var pl := UI.label(", ".join(names) if not names.is_empty() else "nessun modulo", 15, UI.CYAN, UI.font_semi)
	pl.clip_text = true
	pl.custom_minimum_size.x = 320
	mid.add_child(pl)
	var pp := UI.label("%d punti" % D.ship_pts(f), 20, UI.YELLOW, UI.font_bold)
	pp.custom_minimum_size.x = 96
	h.add_child(pp)
	var ed := UI.button("Modifica", 110, 46, 17)
	ed.pressed.connect(func(): _edit(side, i))
	h.add_child(ed)
	var rm := UI.button("Togli", 80, 46, 17)
	rm.pressed.connect(func():
		y["fleets"][side].remove_at(i)
		_save()
		_fill(side))
	h.add_child(rm)
	return pc


func _add(side: int, cls: String) -> void:
	var fl: Array = y["fleets"][side]
	if fl.size() >= D.YARD_MAX:
		return
	fl.append({"cls": cls, "pods": D.default_pods(cls)})
	_save()
	_fill(side)


## flotta a caso: classi e moduli scelti finché restano punti (o 2-4 navi se i punti sono liberi)
func _random(side: int) -> void:
	var b: int = D.YARD_BUDGETS[clampi(int(y.get("budget", 2)), 0, 3)]
	var cap := b if b > 0 else rng.randi_range(150, 260)
	var fl := []
	var tries := 0
	while fl.size() < D.YARD_MAX and tries < 60:
		tries += 1
		var cls: String = CLASSES[rng.randi_range(2, CLASSES.size() - 1)] if rng.randf() < 0.85 else CLASSES[rng.randi_range(0, 1)]
		var pods := []
		for j in int(D.SHIPS[cls]["pods"]):
			var t: String = D.YARD_PODS[rng.randi_range(0, 9)] if rng.randf() < 0.8 else D.YARD_PODS[rng.randi_range(10, D.YARD_PODS.size() - 1)]
			var pd := [t, rng.randi_range(0, 2)]
			if t == "bcpod":
				pd.append("TX" if rng.randf() < 0.6 else "T5000")
			if t == "tractor":
				pd.append(7 + rng.randi_range(0, 1))
			pods.append(pd)
		var s := {"cls": cls, "pods": pods}
		if D.fleet_pts(fl) + D.ship_pts(s) <= cap:
			fl.append(s)
		elif not fl.is_empty() and tries > 20:
			break
	if fl.is_empty():
		fl.append({"cls": "Piccolo", "pods": D.default_pods("Piccolo")})
	y["fleets"][side] = fl
	_save()
	_fill(side)


# ================================================================ modifica di una nave

func _edit(side: int, i: int) -> void:
	if edit_box != null:
		edit_box.queue_free()
	edit_box = Control.new()
	edit_box.size = Vector2(1920, 1080)
	page.add_child(edit_box)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(1920, 1080)
	edit_box.add_child(dim)
	var pc := PanelContainer.new()
	var ps := UI.panel_style(Color(0.03, 0.05, 0.12, 0.98), UI.SIDE[side], 3, 8)
	ps.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", ps)
	pc.position = Vector2(160, 70)
	pc.custom_minimum_size = Vector2(1600, 940)
	edit_box.add_child(pc)
	var f: Dictionary = y["fleets"][side][i]
	var cls: String = f["cls"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	v.add_child(top)
	top.add_child(_fit_img(ShipCard.ship_img(cls), Vector2(420, 150)))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UI.title("%s %s" % [D.SHIPS[cls]["name"], "ABCDEF"[i]], 44))
	var sd: Dictionary = D.SHIPS[cls]
	info.add_child(UI.label("Manovra %d · variazione ±%d · energia %d · burster %d · corazza %d · campo di forza %s · civiltà %d" % [
		sd["mr"], sd["vr"], sd["cap"], sd["burst"], sd["armor"], "no" if int(sd["ff"]) == 0 else str(sd["ff"]), sd["civ"]], 18, UI.TEXT, UI.font_semi))
	var tot := UI.label("", 26, UI.YELLOW, UI.font_bold)
	info.add_child(tot)
	var upd := func():
		tot.text = "Scafo %d punti · totale %d punti" % [D.hull_pts(cls), D.ship_pts(f)]
	upd.call()
	var done := UI.primary(UI.button("Fatto", 200, 60, 24))
	done.pressed.connect(func():
		edit_box.queue_free()
		edit_box = null
		_save()
		_fill(side))
	top.add_child(done)
	var n: int = f["pods"].size()
	if n == 0:
		v.add_child(UI.label("Questa classe non ha moduli: è poco più di un caccia, veloce e manovriera.", 20, UI.MUTED, UI.font_semi))
		return
	v.add_child(UI.heading("Moduli", 24, UI.YELLOW))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	v.add_child(g)
	var rh := clampf(640.0 / ceilf(n / 2.0) - 8.0, 70.0, 120.0)
	for j in n:
		g.add_child(_pod_slot(f, j, rh, upd))


func _pod_slot(f: Dictionary, j: int, rh: float, upd: Callable) -> Control:
	var pc := PanelContainer.new()
	var ps := UI.panel_style(Color("#131c36"), Color("#2b3654"), 1, 4)
	ps.set_content_margin_all(6)
	pc.add_theme_stylebox_override("panel", ps)
	pc.custom_minimum_size = Vector2(770, rh)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	var pd: Array = f["pods"][j]
	var img := _fit_img(UI.tex(D.pod_img(pd[0])), Vector2((rh - 12) * 2.6, rh - 12))
	h.add_child(img)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	col.add_child(r1)
	r1.add_child(UI.label(str(j + 1), 20, UI.MUTED, UI.font_bold))
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(300, 40)
	ob.add_theme_font_size_override("font_size", 17)
	for t in D.YARD_PODS:
		ob.add_item(D.PODS[t]["name"])
	ob.selected = maxi(0, D.YARD_PODS.find(pd[0]))
	r1.add_child(ob)
	var pts := UI.label("", 18, UI.YELLOW, UI.font_bold)
	r1.add_child(pts)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	col.add_child(r2)
	var redraw := func(): pass
	var refresh := func():
		var cur: Array = f["pods"][j]
		pts.text = "%d punti" % D.pod_pts(cur)
		upd.call()
	var build_r2 := func():
		for c in r2.get_children():
			c.queue_free()
		var cur: Array = f["pods"][j]
		r2.add_child(_segmented("Corazza", ["0", "1", "2"], int(cur[1]), func(k):
			f["pods"][j][1] = k
			refresh.call(), 48))
		if cur[0] == "bcpod":
			r2.add_child(_segmented("Caccia", ["Terwillicker-X", "Terwillicker-5000"], 0 if str(cur[2] if cur.size() > 2 else "TX") == "TX" else 1, func(k):
				f["pods"][j] = [cur[0], cur[1], "TX" if k == 0 else "T5000"]
				refresh.call(), 160))
		elif cur[0] == "tractor":
			r2.add_child(_segmented("Civiltà", ["7", "8"], 1 if int(cur[2] if cur.size() > 2 else 7) >= 8 else 0, func(k):
				f["pods"][j] = [cur[0], cur[1], 7 + k]
				refresh.call(), 48))
	ob.item_selected.connect(func(idx: int):
		var t: String = D.YARD_PODS[idx]
		var nd := [t, int(f["pods"][j][1])]
		if t == "bcpod":
			nd.append("TX")
		elif t == "tractor":
			nd.append(8)
		f["pods"][j] = nd
		var tx := UI.tex(D.pod_img(t))
		(img.get_child(0) as TextureRect).texture = tx
		build_r2.call()
		refresh.call())
	build_r2.call()
	refresh.call()
	return pc


# ================================================================ utilità

func _fit_img(tex: Texture2D, box: Vector2) -> Control:
	var fr := PanelContainer.new()
	var fs := UI.panel_style(Color("#07070b"), Color("#2b3654"), 1, 3)
	fs.set_content_margin_all(1)
	fr.add_theme_stylebox_override("panel", fs)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = box
	fr.add_child(tr)
	return fr


func _segmented(label_text: String, items: Array, cur: int, cb: Callable, w := 120) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	if label_text != "":
		var l := UI.label(label_text, 19, UI.TEXT, UI.font_semi)
		h.add_child(l)
		var spc := Control.new()
		spc.custom_minimum_size.x = 6
		h.add_child(spc)
	var btns := []
	for i in items.size():
		var b := UI.button(items[i], w, 42, 17)
		b.toggle_mode = true
		b.button_pressed = i == cur
		btns.append(b)
		h.add_child(b)
	for i in btns.size():
		var k := i
		btns[i].pressed.connect(func():
			for jj in btns.size():
				btns[jj].button_pressed = jj == k
			cb.call(k))
	return h
