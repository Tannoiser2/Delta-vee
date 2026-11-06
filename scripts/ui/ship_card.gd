class_name ShipCard
extends RefCounted
## La scheda di un'unità, come uno Spaceship Log illustrato: l'immagine della classe, i valori della
## tabella, l'energia a blocchi, lo scafo (ponte, motore, campo di forza) e i moduli con le loro immagini
## e lo stato V/D/X. Un clic sull'immagine di un modulo la ingrandisce.

const D = preload("res://scripts/data/dv_data.gd")

const ST_COL := [Color("#3d4762"), Color("#f4e46a"), Color("#ff8a2a"), Color("#e0402a")]
const ST_WORD := ["intatto", "vulnerabile", "danneggiato", "distrutto"]


static func ship_img(cls: String) -> Texture2D:
	return UI.tex("res://assets/ships/%s.webp" % cls)


static func missile_img(mt: String) -> Texture2D:
	return UI.tex("res://assets/missiles/%s.webp" % mt)


# ================================================================ pannello a schede
# intestazione fissa (immagine intera, nome, posizione, energia) + schede Caratteristiche e Moduli

## nome completo dell'unità come compare nella scheda
static func full_name(e: DVEngine, u: Dictionary, hidden: bool) -> String:
	if hidden:
		return "Pedina coperta"
	if u["kind"] == "mis":
		return "%s %s" % [D.MNAME_FULL[u["cls"]], u["label"]]
	if u["kind"] == "bc":
		return "%s %s" % [D.SHIPS[u["cls"]]["name"], u["label"]]
	return e.uname(u)


## etichetta che rimpicciolisce il carattere finché il testo sta nella larghezza
static func fit_label(t: String, w: float, size: int, col: Color, font: Font, min_size := 14) -> Label:
	var sz := size
	while sz > min_size and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > w:
		sz -= 1
	var l := UI.label(t, sz, col, font)
	l.custom_minimum_size.x = w
	l.clip_text = true
	return l


static func _chips(u: Dictionary) -> Array:
	var chips := []
	if u["st"] == "dead":
		chips.append(["DISTRUTTO", UI.RED])
	elif u["st"] != "on":
		chips.append([{"prep": "PRONTO AL LANCIO", "dock": "NELL'HANGAR", "jumped": "SALTATO", "landed": "ATTERRATO", "orbit": "IN ORBITA", "off": "FUORI MAPPA", "spent": "SENZA ENERGIA"}.get(u["st"], str(u["st"]).to_upper()), UI.CYAN])
	if u.get("ffon", false):
		chips.append(["CAMPO DI FORZA", UI.CYAN])
	if int(u.get("jump", 0)) == 1:
		chips.append(["SALTO PREPARATO", UI.YELLOW])
	elif int(u.get("jump", 0)) == 2:
		chips.append(["SALTO AVVIATO", UI.YELLOW])
	if not u.get("alerted", true):
		chips.append(["NON ALLERTATO", UI.MUTED])
	return chips


static func _chip(t: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var cs := UI.panel_style(Color(0, 0, 0, 0.75), col, 2, 3)
	cs.content_margin_top = 1
	cs.content_margin_bottom = 1
	cs.content_margin_left = 6
	cs.content_margin_right = 6
	p.add_theme_stylebox_override("panel", cs)
	p.add_child(UI.label(t, 13, col, UI.font_bold))
	return p


## intestazione sempre visibile: immagine intera in un riquadro della sua misura, pedina, stati,
## nome (che si adatta alla larghezza), lato e posizione, energia
static func header(e: DVEngine, u: Dictionary, hidden: bool, full: bool, w: float) -> Control:
	UI.init_fonts()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	var side_w := 140.0
	var art: Texture2D = null
	if not hidden:
		art = missile_img(u["cls"]) if u["kind"] == "mis" else ship_img(u["cls"])
	var ih := 112.0
	var iw := w - side_w - 10
	if art != null:
		var asp := float(art.get_width()) / maxf(1.0, art.get_height())
		iw = minf(iw, ih * asp)
		ih = iw / asp
	var fr := PanelContainer.new()
	var fs := UI.panel_style(Color("#07070b"), UI.SIDE[u["side"]], 2, 4)
	fs.set_content_margin_all(2)
	fr.add_theme_stylebox_override("panel", fs)
	fr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(fr)
	if art != null:
		var tr := TextureRect.new()
		tr.texture = art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(iw, ih)
		if u["st"] == "dead":
			tr.modulate = Color(0.45, 0.3, 0.28)
		fr.add_child(tr)
	else:
		var ph := Control.new()
		ph.custom_minimum_size = Vector2(iw, ih)
		fr.add_child(ph)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sv)
	sv.add_child(UI.icon_rect(UI.counter_tex(u["side"], u["kind"], u["cls"], u["label"], hidden or (u["kind"] == "ship" and u.get("ffon", false))), Vector2(52, 52)))
	if not hidden:
		for ch in _chips(u):
			sv.add_child(_chip(ch[0], ch[1]))
	vb.add_child(fit_label(full_name(e, u, hidden), w, 30, UI.SIDE[u["side"]], UI.font_title, 16))
	var line := "%s · %s" % [D.SIDE_NAMES[u["side"]], e.sc["sides"][u["side"]]]
	if u["st"] == "on":
		line += "  ·  %s · ore %s · vel. %d" % [e.hcode(u["hex"]), D.DIR_NAMES[u["dir"]], u["v"]]
	vb.add_child(fit_label(line, w, 16, UI.TEXT, UI.font_semi, 12))
	if full and not hidden and u["kind"] in ["ship", "bc"]:
		var tot: int
		var left: int
		var txt: String
		if u["kind"] == "ship":
			tot = int(u["cap"]) / e.burn(u)
			left = e.energy(u) / e.burn(u)
			txt = "%d/%d blocchi da %d" % [left, tot, e.burn(u)]
		else:
			tot = 15
			left = int(u["eu"])
			txt = "%d/15 unità" % left
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(UI.label("ENERGIA", 14, UI.YELLOW, UI.font_bold))
		var bar := BlockBar.new()
		bar.total = tot
		bar.left = left
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(bar)
		h.add_child(UI.label(txt, 14, UI.TEXT, UI.font_semi))
		vb.add_child(h)
	return vb


## scheda Caratteristiche: valori, scafo, missili pronti (o la descrizione del missile)
static func stats(e: DVEngine, u: Dictionary, hidden: bool, full: bool, w: float) -> Control:
	UI.init_fonts()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	if hidden:
		body.add_child(UI.wrap(UI.label("Pedina coperta: non ancora individuata. Si scopre entro 3 esagoni da una vostra astronave all'inizio della vostra fase di comando, o con la ricerca attiva.", 16, UI.MUTED, UI.font_body), w))
		return body
	match u["kind"]:
		"ship":
			var sd: Dictionary = e.sdef(u)
			var ffc := "—" if int(sd["ff"]) == 0 else str(sd["ff"])
			body.add_child(_tiles([
				[u["pods"].size(), "moduli"], ["±%d" % sd["vr"], "variazione"], [e.mr(u), "manovra", UI.YELLOW if e.mr(u) == int(sd["mr"]) else UI.RED],
				[sd["burst"], "burster"], [sd["armor"], "corazza"],
				[ffc, "campo forza", UI.CYAN if u.get("ffon", false) else UI.YELLOW], [sd["civ"], "civiltà"], [sd["tp"], "puntamento"],
				["sì" if sd["stream"] else "no", "aerodin."], [e.bc_count(u), "com. batt."]], w))
			body.add_child(_section("Scafo"))
			var hull := HBoxContainer.new()
			hull.add_theme_constant_override("separation", 6)
			var parts := [["bridge", "Ponte"], ["engine", "Motore"]]
			if int(sd["ff"]) > 0:
				parts.append(["ff", "Campo di forza"])
			var pw := (w - 6 * (parts.size() - 1)) / parts.size()
			for p in parts:
				hull.add_child(_part_tile(p[1], e.part_state(u, p[0]), int(sd["armor"]), pw))
			body.add_child(hull)
			var prep := e.prepared_of(u)
			if not prep.is_empty():
				body.add_child(_section("Pronti sopra la nave"))
				var hb := HFlowContainer.new()
				hb.add_theme_constant_override("h_separation", 6)
				hb.add_theme_constant_override("v_separation", 6)
				for m in prep:
					var mp := PanelContainer.new()
					mp.add_theme_stylebox_override("panel", UI.panel_style(Color("#131c36"), Color("#2b3654"), 1, 4))
					var mv := VBoxContainer.new()
					mp.add_child(mv)
					mv.add_child(UI.icon_rect(missile_img(m["cls"]) if full else UI.counter_tex(m["side"], "mis", m["cls"], m["label"], true), Vector2(120, 24) if full else Vector2(40, 40)))
					mv.add_child(UI.label(("%s (mod. %d)" % [D.MNAME[m["cls"]], int(m["pod"]) + 1]) if full else "coperta", 13, UI.TEXT, UI.font_semi))
					hb.add_child(mp)
				body.add_child(hb)
			body.add_child(UI.wrap(UI.label("Valori in giallo: originali; in rosso: ridotti dai danni. Gli stati delle parti: V vulnerabile, D danneggiato, X distrutto.", 14, UI.MUTED, UI.font_body), w))
		"bc":
			var sd: Dictionary = e.sdef(u)
			body.add_child(_tiles([["±%d" % sd["vr"], "variazione"], [e.mr(u), "manovra"], [sd["burst"], "burster"],
				[sd["armor"], "corazza"], [sd["tp"], "puntamento"]], w))
			body.add_child(_section("Scafo"))
			var hull := HBoxContainer.new()
			hull.add_theme_constant_override("separation", 6)
			for p in [["bridge", "Ponte"], ["engine", "Motore"]]:
				hull.add_child(_part_tile(p[1], e.part_state(u, p[0]), int(sd["armor"]), (w - 6) / 2))
			body.add_child(hull)
			var host: Dictionary = e.units.get(u.get("host", ""), {})
			if not host.is_empty():
				body.add_child(UI.label("Nave madre: %s" % e.uname(host), 16, UI.MUTED, UI.font_semi))
		"mis":
			_missile(e, u, body, w)
	return body


## scheda Moduli: i moduli con l'immagine intera in riquadri della stessa misura; un clic mostra il dettaglio
static func pods(e: DVEngine, u: Dictionary, full: bool, w: float, detail := -1, on_pick := Callable()) -> Control:
	UI.init_fonts()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var n: int = u["pods"].size()
	if detail >= 0 and detail < n:
		var p: Dictionary = u["pods"][detail]
		var st := e.pod_state(u, detail)
		var tex := UI.tex(D.pod_img(p["t"]))
		var asp := float(tex.get_width()) / maxf(1.0, tex.get_height())
		var fr := PanelContainer.new()
		var fs := UI.panel_style(Color("#07070b"), ST_COL[st], 2, 4)
		fs.set_content_margin_all(2)
		fr.add_theme_stylebox_override("panel", fs)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(w - 8, (w - 8) / asp)
		fr.add_child(tr)
		body.add_child(fr)
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 8)
		hr.add_child(_badge(st))
		hr.add_child(UI.label("Modulo %d · %s" % [detail + 1, D.PODS[p["t"]]["name"]], 22, UI.YELLOW, UI.font_bold))
		body.add_child(hr)
		body.add_child(UI.label(_pod_info(e, u, detail, full), 16, UI.CYAN, UI.font_semi))
		body.add_child(UI.wrap(UI.label(D.POD_TEXT.get(p["t"], ""), 17, UI.TEXT, UI.font_body), w))
		var back := UI.button("Torna ai moduli", 0, 40, 17)
		back.pressed.connect(func(): on_pick.call(-1))
		body.add_child(back)
		return body
	var cols := 2 if n <= 4 else 3
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	body.add_child(g)
	var tw := (w - 6 * (cols - 1)) / cols
	for i in n:
		g.add_child(_pod_card(e, u, i, full, tw, on_pick))
	body.add_child(UI.wrap(UI.label("Tocca un modulo per leggerne la descrizione. NG non guidati, G guidati, I intelligenti, M MIMS; * = da preparare prima del lancio.", 14, UI.MUTED, UI.font_body), w))
	return body


static func _pod_info(e: DVEngine, u: Dictionary, i: int, full: bool) -> String:
	var p: Dictionary = u["pods"][i]
	var pd: Dictionary = D.PODS[p["t"]]
	var st := e.pod_state(u, i)
	var info := "cor. %d · %s" % [p["armor"], ST_WORD[st]]
	if pd["lp"] and full:
		var bits := []
		for mt in D.MTYPES:
			var k := int(p["ms"].get(mt, 0))
			if k > 0:
				bits.append("%s %d%s" % [{"ug": "NG", "g": "G", "i": "I", "m": "M"}[mt], k, "*" if mt in pd["prep"] else ""])
		if not bits.is_empty():
			info = " ".join(bits)
	if p["t"] == "bcpod" and p["bc"] != "":
		var b: Dictionary = e.units[p["bc"]]
		info = "%s: %s" % [b["label"], {"dock": "a bordo", "prep": "pronto", "on": "in volo", "dead": "perso"}.get(b["st"], b["st"])]
	if p["t"] == "tractor":
		info = "civiltà %d · cor. %d" % [p["civ"], p["armor"]]
	return info


static func _pod_card(e: DVEngine, u: Dictionary, i: int, full: bool, w: float, on_pick: Callable) -> Control:
	var p: Dictionary = u["pods"][i]
	var pd: Dictionary = D.PODS[p["t"]]
	var st := e.pod_state(u, i)
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, 0)
	b.focus_mode = Control.FOCUS_NONE
	var s := UI.panel_style(Color("#131c36"), ST_COL[st], 2, 4)
	var sh := UI.panel_style(Color("#1b2748"), UI.YELLOW if st == 0 else ST_COL[st], 2, 4)
	for k in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, s)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	if on_pick.is_valid():
		b.pressed.connect(func(): on_pick.call(i))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.position = Vector2(3, 3)
	b.add_child(v)
	var ih := (w - 6) / 2.6
	var img := Control.new()
	img.custom_minimum_size = Vector2(w - 6, ih)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = UI.tex(D.pod_img(p["t"]))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = Vector2(w - 6, ih)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if st == 3:
		tr.modulate = Color(0.4, 0.3, 0.3)
	elif st == 2:
		tr.modulate = Color(0.95, 0.75, 0.65)
	img.add_child(tr)
	var bd := _badge(st)
	bd.custom_minimum_size = Vector2(22, 22)
	bd.position = Vector2(2, 2)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.add_child(bd)
	var num := UI.label(str(i + 1), 15, UI.TEXT, UI.font_bold)
	num.position = Vector2(w - 22, 0)
	num.add_theme_color_override("font_shadow_color", Color.BLACK)
	num.add_theme_constant_override("shadow_offset_x", 2)
	num.add_theme_constant_override("shadow_offset_y", 2)
	img.add_child(num)
	if st == 3:
		var cx := Cross.new()
		cx.size = Vector2(w - 6, ih)
		cx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.add_child(cx)
	v.add_child(img)
	var nl := fit_label(pd["name"], w - 10, 15, UI.TEXT if st < 3 else UI.RED, UI.font_bold, 11)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var il := fit_label(_pod_info(e, u, i, full), w - 10, 13, UI.CYAN, UI.font_semi, 10)
	il.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(il)
	b.custom_minimum_size.y = ih + 44
	return b


## scheda completa. full = si vedono energia e missili (proprie unità o partita finita)
static func build(e: DVEngine, u: Dictionary, hidden: bool, full: bool, w: float) -> Control:
	UI.init_fonts()
	var pc := PanelContainer.new()
	var sb := UI.panel_style(UI.PANEL, UI.SIDE[u["side"]], 2, 6)
	sb.set_content_margin_all(0)
	sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	# ---- immagine e intestazione
	var art: Texture2D = null
	if not hidden:
		art = missile_img(u["cls"]) if u["kind"] == "mis" else ship_img(u["cls"])
	vb.add_child(_banner(e, u, art, hidden, w))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var mc := MarginContainer.new()
	for k in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(k, 10)
	mc.add_child(body)
	vb.add_child(mc)
	var iw := w - 24
	if hidden:
		body.add_child(UI.wrap(UI.label("Pedina coperta: non ancora individuata. Si scopre entro 3 esagoni da una vostra astronave all'inizio della vostra fase di comando, o con la ricerca attiva.", 17, UI.MUTED, UI.font_body), iw))
		return pc
	match u["kind"]:
		"ship":
			_ship(e, u, full, body, iw)
		"bc":
			_bc(e, u, full, body, iw)
		"mis":
			_missile(e, u, body, iw)
	return pc


static func _banner(e: DVEngine, u: Dictionary, art: Texture2D, hidden: bool, w: float) -> Control:
	var h := w * 0.36
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h + 64)
	c.clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color("#07070b")
	bg.size = Vector2(w, h)
	c.add_child(bg)
	if art != null:
		var tr := TextureRect.new()
		tr.texture = art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = Vector2(w, h)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if u["st"] == "dead":
			tr.modulate = Color(0.45, 0.3, 0.28)
		c.add_child(tr)
	# sfumatura verso il basso
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.05, 0.05, 0.07, 0.0), Color(0.05, 0.05, 0.07, 0.95)])
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0.45)
	gt.fill_to = Vector2(0, 1)
	var gtr := TextureRect.new()
	gtr.texture = gt
	gtr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gtr.size = Vector2(w, h)
	gtr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(gtr)
	# la pedina in alto a destra
	var ct := UI.icon_rect(UI.counter_tex(u["side"], u["kind"], u["cls"], u["label"], hidden or (u["kind"] == "ship" and u.get("ffon", false))), Vector2(58, 58))
	ct.position = Vector2(w - 66, 8)
	c.add_child(ct)
	# stati speciali sopra l'immagine
	var chips := []
	if u["st"] == "dead":
		chips.append(["DISTRUTTO", UI.RED])
	elif u["st"] != "on":
		chips.append([{"prep": "PRONTO AL LANCIO", "dock": "NELL'HANGAR", "jumped": "SALTATO", "landed": "ATTERRATO", "orbit": "IN ORBITA", "off": "FUORI MAPPA", "spent": "SENZA ENERGIA"}.get(u["st"], u["st"]), UI.CYAN])
	if u.get("ffon", false):
		chips.append(["CAMPO DI FORZA ATTIVO", UI.CYAN])
	if int(u.get("jump", 0)) == 1:
		chips.append(["SALTO PREPARATO", UI.YELLOW])
	elif int(u.get("jump", 0)) == 2:
		chips.append(["SALTO AVVIATO", UI.YELLOW])
	if not u.get("alerted", true):
		chips.append(["NON ALLERTATO", UI.MUTED])
	var x := 10.0
	for ch in chips:
		var p := PanelContainer.new()
		var cs := UI.panel_style(Color(0, 0, 0, 0.75), ch[1], 2, 3)
		cs.content_margin_top = 1
		cs.content_margin_bottom = 2
		cs.content_margin_left = 8
		cs.content_margin_right = 8
		p.add_theme_stylebox_override("panel", cs)
		p.add_child(UI.label(ch[0], 15, ch[1], UI.font_bold))
		p.position = Vector2(x, h - 34)
		c.add_child(p)
		x += 12 + UI.font_bold.get_string_size(ch[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18
	# nome e lato sotto l'immagine
	var nm := "Pedina coperta" if hidden else e.uname(u)
	if u["kind"] == "mis" and not hidden:
		nm = "%s %s" % [D.MNAME_FULL[u["cls"]], u["label"]]
	elif u["kind"] == "bc" and not hidden:
		nm = "%s %s" % [D.SHIPS[u["cls"]]["name"], u["label"]]
	var t := UI.title(nm, 30, UI.SIDE[u["side"]])
	t.position = Vector2(12, h - 4)
	t.clip_text = true
	t.size = Vector2(w - 24, 40)
	c.add_child(t)
	var line := "%s · %s" % [D.SIDE_NAMES[u["side"]], e.sc["sides"][u["side"]]]
	if u["st"] == "on":
		line += "   ·   %s · ore %s · vel. %d" % [e.hcode(u["hex"]), D.DIR_NAMES[u["dir"]], u["v"]]
	var l := UI.label(line, 16, UI.TEXT, UI.font_semi)
	l.position = Vector2(12, h + 36)
	l.size = Vector2(w - 24, 24)
	l.clip_text = true
	c.add_child(l)
	return c


## riquadro di un valore: numero grande e didascalia
static func _tile(val: String, cap: String, col := UI.YELLOW, wt := 84.0) -> Control:
	var p := PanelContainer.new()
	var s := UI.panel_style(Color("#131c36"), Color("#2b3654"), 1, 4)
	s.set_content_margin_all(2)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(wt, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -5)
	p.add_child(v)
	var a := UI.label(val, 19, col, UI.font_bold)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var b := UI.label(cap.to_upper(), 10, UI.MUTED, UI.font_semi)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	return p


static func _tiles(items: Array, iw: float) -> Control:
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	var tw := (iw - 24) / 5.0
	for it in items:
		g.add_child(_tile(str(it[0]), it[1], it[2] if it.size() > 2 else UI.YELLOW, tw))
	return g


static func _section(t: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = UI.STRIPE
	bar.custom_minimum_size = Vector2(5, 18)
	h.add_child(bar)
	h.add_child(UI.label(t.to_upper(), 16, Color.WHITE, UI.font_bold))
	var line := ColorRect.new()
	line.color = Color(UI.METAL, 0.3)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h


## barra dell'energia a blocchi, come le caselle del log
class BlockBar extends Control:
	var total := 1
	var left := 0
	var unit := 1

	func _draw() -> void:
		var n := clampi(total, 1, 60)
		var gap := 2.0
		var bw := (size.x - gap * (n - 1)) / n
		for i in n:
			var r := Rect2(i * (bw + gap), 0, bw, size.y)
			var on := i < left
			draw_rect(r, UI.HEX if on else Color("#222b45"))
			if on:
				draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(1, 0.8, 0.5, 0.6))


static func _energy(e: DVEngine, u: Dictionary, body: VBoxContainer, iw: float) -> void:
	var en := e.energy(u)
	var bl := en / e.burn(u)
	var tot := int(u["cap"]) / e.burn(u)
	var h := HBoxContainer.new()
	h.add_child(UI.label("ENERGIA", 16, UI.YELLOW, UI.font_bold))
	var t := UI.label("  %d / %d blocchi  ·  %d unità  ·  blocco = %d" % [bl, tot, en, e.burn(u)], 16, UI.TEXT, UI.font_semi)
	h.add_child(t)
	body.add_child(h)
	var bar := BlockBar.new()
	bar.total = tot
	bar.left = bl
	bar.custom_minimum_size = Vector2(iw, 16)
	body.add_child(bar)


static func _ship(e: DVEngine, u: Dictionary, full: bool, body: VBoxContainer, iw: float) -> void:
	var sd: Dictionary = e.sdef(u)
	var ffc := "—" if int(sd["ff"]) == 0 else str(sd["ff"])
	body.add_child(_tiles([
		[u["pods"].size(), "moduli"], ["±%d" % sd["vr"], "variazione"], [e.mr(u), "manovra", UI.YELLOW if e.mr(u) == int(sd["mr"]) else UI.RED],
		[sd["burst"], "burster"], [sd["armor"], "corazza"],
		[ffc, "campo forza", UI.CYAN if u.get("ffon", false) else UI.YELLOW], [sd["civ"], "civiltà"], [sd["tp"], "puntamento"],
		["sì" if sd["stream"] else "no", "aerodin."], [e.bc_count(u), "com. batt."]], iw))
	if full:
		_energy(e, u, body, iw)
	body.add_child(_section("Scafo"))
	var hull := HBoxContainer.new()
	hull.add_theme_constant_override("separation", 6)
	var parts := [["bridge", "Ponte"], ["engine", "Motore"]]
	if int(sd["ff"]) > 0:
		parts.append(["ff", "Campo di forza"])
	var pw := (iw - 6 * (parts.size() - 1)) / parts.size()
	for p in parts:
		hull.add_child(_part_tile(p[1], e.part_state(u, p[0]), int(sd["armor"]), pw))
	body.add_child(hull)
	body.add_child(_section("Moduli"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	body.add_child(g)
	var tw := (iw - 6) / 2.0
	for i in u["pods"].size():
		g.add_child(_pod_tile(e, u, i, full, tw, body))
	var prep := e.prepared_of(u)
	if not prep.is_empty():
		body.add_child(_section("Pronti sopra la nave"))
		var hb := HFlowContainer.new()
		hb.add_theme_constant_override("h_separation", 6)
		for m in prep:
			var mp := PanelContainer.new()
			mp.add_theme_stylebox_override("panel", UI.panel_style(Color("#131c36"), Color("#2b3654"), 1, 4))
			var mv := VBoxContainer.new()
			mp.add_child(mv)
			mv.add_child(UI.icon_rect(missile_img(m["cls"]) if full else UI.counter_tex(m["side"], "mis", m["cls"], m["label"], true), Vector2(120, 34)))
			mv.add_child(UI.label(("%s (mod. %d)" % [D.MNAME[m["cls"]], int(m["pod"]) + 1]) if full else "coperta", 14, UI.TEXT, UI.font_semi))
			hb.add_child(mp)
		body.add_child(hb)


static func _part_tile(name: String, st: int, armor: int, w: float) -> Control:
	var p := PanelContainer.new()
	var s := UI.panel_style(Color("#131c36"), ST_COL[st], 2, 4)
	s.set_content_margin_all(5)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(w, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	h.add_child(_badge(st))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.add_child(UI.label(name, 17, UI.TEXT if st < 3 else UI.RED, UI.font_bold))
	v.add_child(UI.label("%s · cor. %d" % [ST_WORD[st], armor], 13, UI.MUTED, UI.font_body))
	h.add_child(v)
	return p


static func _badge(st: int) -> Control:
	var b := PanelContainer.new()
	var s := UI.panel_style(ST_COL[st] if st > 0 else Color("#24212a"), Color(0, 0, 0, 0.6), 1, 3)
	s.set_content_margin_all(0)
	b.add_theme_stylebox_override("panel", s)
	b.custom_minimum_size = Vector2(28, 28)
	var l := UI.label(["", "V", "D", "X"][st], 19, UI.INK, UI.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	return b


## X rossa sopra le parti distrutte
class Cross extends Control:
	func _draw() -> void:
		draw_line(Vector2(6, 6), size - Vector2(6, 6), Color(UI.RED, 0.85), 5.0)
		draw_line(Vector2(size.x - 6, 6), Vector2(6, size.y - 6), Color(UI.RED, 0.85), 5.0)


static func _pod_tile(e: DVEngine, u: Dictionary, i: int, full: bool, w: float, body: VBoxContainer) -> Control:
	var p: Dictionary = u["pods"][i]
	var pd: Dictionary = D.PODS[p["t"]]
	var st := e.pod_state(u, i)
	var pc := PanelContainer.new()
	var s := UI.panel_style(Color("#131c36"), ST_COL[st], 2, 4)
	s.set_content_margin_all(3)
	pc.add_theme_stylebox_override("panel", s)
	pc.custom_minimum_size = Vector2(w, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var ih := (w - 6) * 0.36
	var img := Control.new()
	img.custom_minimum_size = Vector2(w - 6, ih)
	img.clip_contents = true
	var tb := TextureButton.new()
	tb.texture_normal = UI.tex(D.pod_img(p["t"]))
	tb.ignore_texture_size = true
	tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
	tb.size = Vector2(w - 6, ih)
	tb.tooltip_text = "%s — %s" % [pd["name"], D.POD_TEXT.get(p["t"], "")]
	if st == 3:
		tb.modulate = Color(0.4, 0.3, 0.3)
	elif st == 2:
		tb.modulate = Color(0.95, 0.75, 0.65)
	var key: String = p["t"]
	tb.pressed.connect(func(): _zoom(body, key, w * 2 + 6))
	img.add_child(tb)
	var bd := _badge(st)
	bd.position = Vector2(4, 4)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.add_child(bd)
	var num := UI.label(str(i + 1), 18, UI.TEXT, UI.font_bold)
	num.position = Vector2(w - 26, 2)
	num.add_theme_color_override("font_shadow_color", Color.BLACK)
	num.add_theme_constant_override("shadow_offset_x", 2)
	num.add_theme_constant_override("shadow_offset_y", 2)
	img.add_child(num)
	if st == 3:
		var cx := Cross.new()
		cx.size = Vector2(w - 6, ih)
		cx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.add_child(cx)
	v.add_child(img)
	var nl := UI.label(pd["name"], 16, UI.TEXT if st < 3 else UI.RED, UI.font_bold)
	nl.clip_text = true
	nl.custom_minimum_size.x = w - 10
	v.add_child(nl)
	var info := "cor. %d · %s" % [p["armor"], ST_WORD[st]]
	if pd["lp"] and full:
		var bits := []
		for mt in D.MTYPES:
			var n := int(p["ms"].get(mt, 0))
			if n > 0:
				bits.append("%s %d%s" % [{"ug": "NG", "g": "G", "i": "I", "m": "M"}[mt], n, "*" if mt in pd["prep"] else ""])
		if not bits.is_empty():
			info = " ".join(bits)
	if p["t"] == "bcpod" and p["bc"] != "":
		var b: Dictionary = e.units[p["bc"]]
		info = "%s: %s" % [b["label"], {"dock": "a bordo", "prep": "pronto", "on": "in volo", "dead": "perso"}.get(b["st"], b["st"])]
	if p["t"] == "tractor":
		info = "civiltà %d · cor. %d" % [p["civ"], p["armor"]]
	var il := UI.label(info, 14, UI.CYAN, UI.font_semi)
	il.clip_text = true
	il.custom_minimum_size.x = w - 10
	v.add_child(il)
	return pc


static func _zoom(body: VBoxContainer, key: String, w: float) -> void:
	for c in body.get_children():
		if c.has_meta("zoom"):
			var same: bool = c.get_meta("zoom") == key
			c.queue_free()
			if same:
				return
	var box := VBoxContainer.new()
	box.set_meta("zoom", key)
	box.add_child(UI.icon_rect(UI.tex(D.pod_img(key)), Vector2(w, w * 0.39)))
	box.add_child(UI.wrap(UI.label(D.PODS[key]["name"].to_upper() + " — " + D.POD_TEXT.get(key, ""), 15, UI.TEXT, UI.font_body), w))
	body.add_child(box)
	body.move_child(box, 0)


static func _bc(e: DVEngine, u: Dictionary, full: bool, body: VBoxContainer, iw: float) -> void:
	var sd: Dictionary = e.sdef(u)
	body.add_child(_tiles([["±%d" % sd["vr"], "variazione"], [e.mr(u), "manovra"], [sd["burst"], "burster"],
		[sd["armor"], "corazza"], [sd["tp"], "puntamento"]], iw))
	var h := HBoxContainer.new()
	h.add_child(UI.label("ENERGIA", 16, UI.YELLOW, UI.font_bold))
	h.add_child(UI.label("  %d / 15 unità" % u["eu"], 16, UI.TEXT, UI.font_semi))
	body.add_child(h)
	var bar := BlockBar.new()
	bar.total = 15
	bar.left = int(u["eu"])
	bar.custom_minimum_size = Vector2(iw, 14)
	body.add_child(bar)
	body.add_child(_section("Scafo"))
	var hull := HBoxContainer.new()
	hull.add_theme_constant_override("separation", 6)
	for p in [["bridge", "Ponte"], ["engine", "Motore"]]:
		hull.add_child(_part_tile(p[1], e.part_state(u, p[0]), int(sd["armor"]), (iw - 6) / 2))
	body.add_child(hull)
	var host: Dictionary = e.units.get(u.get("host", ""), {})
	if not host.is_empty():
		body.add_child(UI.label("Nave madre: %s" % e.uname(host), 16, UI.MUTED, UI.font_semi))


static func _missile(e: DVEngine, u: Dictionary, body: VBoxContainer, iw: float) -> void:
	var mt: String = u["cls"]
	if mt != "ug":
		body.add_child(_tiles([[u["civ"], "civiltà"], ["±%d" % e.vr(u), "variazione"], [e.mr(u), "manovra"], [u["eu"], "energia", UI.CYAN], [u["v"], "velocità"]], iw))
	else:
		body.add_child(_tiles([[u["civ"], "civiltà"], [u["v"], "velocità"]], iw))
	var txt: String = {"ug": "Nessuna manovra: accelera di 1 a ogni fase di comando del suo lato.",
		"g": "Manovra solo con il comando di battaglia «Guida» della nave che l'ha lanciato.",
		"i": "Manovra da solo a ogni fase di comando; ogni comando consuma un'unità di energia.",
		"m": "Come un intelligente; una volta può aprirsi e lanciare quattro missili non guidati."}[mt]
	body.add_child(UI.wrap(UI.label(txt, 16, UI.TEXT, UI.font_body), iw))
	if mt == "g":
		var host: Dictionary = e.units.get(u.get("host", ""), {})
		if not host.is_empty():
			body.add_child(UI.label("Nave di controllo: %s" % e.uname(host), 16, UI.MUTED, UI.font_semi))
	if mt == "m" and u.get("mims_used", false):
		body.add_child(UI.label("Ha già lanciato i suoi quattro missili.", 16, UI.MUTED, UI.font_semi))
