extends Control
## La mappa in 2D: lo spazio nero con la griglia esagonale arancione e le sigle degli esagoni come sul
## tabellone SPI, le pedine originali orientate nelle 12 direzioni con il segnalino di velocità,
## e i suggerimenti per i comandi (percorsi previsti, bersagli, punti di lancio).
## Si sposta trascinando, si ingrandisce con la rotella (o con due dita).

signal hex_clicked(h: Vector2i)
signal hex_hovered(h: Vector2i)

const D = preload("res://scripts/data/dv_data.gd")
const S := 48.0

var eng: DVEngine
var state := {"units": {}, "fx": [], "maps": {}}
var viewer: Array = [0, 1]       # lati di cui si vedono le pedine coperte
var ov := {}                     # sovrapposizioni: vedi game_view
var world: Node2D
var grid: Node2D
var grid_alpha := 1.0
var layer: Node2D
var zoom := 0.6
var _drag := false
var _drag_from := Vector2.ZERO
var _moved := false
var _maps_key := ""
var hover := Vector2i(-999, -999)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	world = Node2D.new()
	add_child(world)
	grid = GridLayer.new()
	grid.board = self
	world.add_child(grid)
	layer = UnitLayer.new()
	layer.board = self
	world.add_child(layer)
	world.scale = Vector2(zoom, zoom)


func set_engine(e: DVEngine) -> void:
	eng = e


func set_state(st: Dictionary) -> void:
	state = st
	if grid == null:
		return
	var mk := str(st.get("maps", {}).keys())
	if mk != _maps_key:
		_maps_key = mk
		grid.queue_redraw()
	layer.queue_redraw()


func redraw() -> void:
	layer.queue_redraw()


func maps() -> Dictionary:
	var m: Dictionary = state.get("maps", {})
	if m.is_empty() and eng != null:
		m = eng.maps
	return m


func world_bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for key in maps():
		var p: PackedStringArray = str(key).split(",")
		var bx := int(p[0])
		var by := int(p[1])
		var a := Hex.center(Vector2i(bx * 16, by * 18), S) - Vector2(S, S)
		var b := Hex.center(Vector2i(bx * 16 + 15, by * 18 + 17), S) + Vector2(S, S * 1.8)
		var rr := Rect2(a, b - a)
		r = rr if first else r.merge(rr)
		first = false
	return r


## inquadra le unità in gioco (con un po' di margine), oppure tutte le mappe
func fit(all_maps := false) -> void:
	var r := units_bounds() if not all_maps else Rect2()
	if r.size.x <= 0:
		r = world_bounds()
	if r.size.x <= 0 or size.x <= 0:
		return
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y) * 0.96, 0.12, 3.0)
	world.scale = Vector2(zoom, zoom)
	world.position = size * 0.5 - r.get_center() * zoom


func units_bounds() -> Rect2:
	var units: Dictionary = state.get("units", {})
	if units.is_empty() and eng != null:
		for id in eng.order:
			var u: Dictionary = eng.units[id]
			if u["st"] == "on":
				units[id] = {"p": Hex.center(u["hex"], 1.0)}
	if units.is_empty():
		return Rect2()
	var r := Rect2()
	var first := true
	for id in units:
		var p: Vector2 = units[id]["p"] * S
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	r = r.grow(S * 4.0)
	var minw := S * 1.5 * 18
	var minh := S * 1.732 * 12
	if r.size.x < minw:
		r = r.grow_individual((minw - r.size.x) / 2, 0, (minw - r.size.x) / 2, 0)
	if r.size.y < minh:
		r = r.grow_individual(0, (minh - r.size.y) / 2, 0, (minh - r.size.y) / 2)
	return r


func center_on(p: Vector2) -> void:
	world.position = size * 0.5 - p * S * zoom


func to_world(screen: Vector2) -> Vector2:
	return (screen - world.position) / zoom


func hex_at(screen: Vector2) -> Vector2i:
	return Hex.at(to_world(screen), S)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom_at(ev.position, 1.12)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom_at(ev.position, 1.0 / 1.12)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				_drag = true
				_moved = false
				_drag_from = ev.position
			else:
				if _drag and not _moved and ev.button_index == MOUSE_BUTTON_LEFT:
					hex_clicked.emit(hex_at(ev.position))
				_drag = false
	elif ev is InputEventMouseMotion:
		if _drag:
			if (ev.position - _drag_from).length() > 6 or _moved:
				_moved = true
				world.position += ev.relative
		var h := hex_at(ev.position)
		if h != hover:
			hover = h
			hex_hovered.emit(h)
			layer.queue_redraw()
	elif ev is InputEventMagnifyGesture:
		_zoom_at(ev.position, ev.factor)
	elif ev is InputEventPanGesture:
		world.position -= ev.delta * 8.0


func _zoom_at(p: Vector2, f: float) -> void:
	var before := to_world(p)
	zoom = clampf(zoom * f, 0.1, 3.5)
	world.scale = Vector2(zoom, zoom)
	world.position = p - before * zoom
	grid.queue_redraw()


func _process(_d: float) -> void:
	if not state.get("fx", []).is_empty():
		layer.queue_redraw()


# ================================================================ griglia

func set_grid_alpha(a: float) -> void:
	grid_alpha = clampf(a, 0.0, 1.0)
	if grid != null:
		grid.queue_redraw()


class GridLayer extends Node2D:
	var board

	func _draw() -> void:
		UI.init_fonts()
		var S: float = board.S
		var mp: Dictionary = board.maps()
		var ga: float = board.grid_alpha
		var col := Color(UI.HEX, 0.85 * ga)
		var dot := Color(UI.HEX, 0.9)
		var fine: bool = board.zoom > 0.32
		for key in mp:
			var p: PackedStringArray = str(key).split(",")
			var bx := int(p[0])
			var by := int(p[1])
			var o0 := Hex.center(Vector2i(bx * 16, by * 18), S) - Vector2(S * 0.75, S * 0.87)
			draw_rect(Rect2(o0, Vector2(S * 24.0, S * 31.177)), Color(0.01, 0.01, 0.03, 0.72))
			# logo e bussola al centro della mappa, come sul tabellone
			var c := Hex.center(Vector2i(bx * 16 + 8, by * 18 + 8), S)
			_compass(c + Vector2(0, S * 1.2), S)
			var logo := "DeltaVee"
			var fs := int(S * 2.1)
			var w := UI.font_title.get_string_size(logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(UI.font_title, c + Vector2(-w / 2, -S * 1.6), logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.83, 0.8, 0.22))
			var L: String = mp[key]
			var fl := int(S * 3.4)
			var wl := UI.font_title.get_string_size(L, HORIZONTAL_ALIGNMENT_LEFT, -1, fl).x
			draw_string(UI.font_title, Hex.center(Vector2i(bx * 16 + 1, by * 18 + 1), S) + Vector2(-wl * 0.2, S * 0.9), L, HORIZONTAL_ALIGNMENT_LEFT, -1, fl, Color(UI.YELLOW, 0.1))
			for q in range(bx * 16, bx * 16 + 16):
				for r in range(by * 18, by * 18 + 18):
					var h := Vector2i(q, r)
					var cc := Hex.center(h, S)
					var pts := Hex.corners(cc, S)
					pts.append(pts[0])
					if ga > 0.01:
						draw_polyline(pts, col, 2.0)
					# puntino al centro: resta anche senza griglia
					draw_circle(cc, S * 0.06, dot)
					if fine and ga > 0.01:
						var txt := "%02d%02d" % [q - bx * 16 + 1, r - by * 18 + 1]
						draw_string(UI.font_mono, cc + Vector2(-S * 0.42, -S * 0.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(S * 0.3), Color(UI.HEX, 0.9 * ga))
		# pianeti e asteroidi
		if board.eng != null:
			var ast: Texture2D = UI.tex("res://assets/markers/asteroidi.png")
			for h in board.eng.asteroids:
				var cc := Hex.center(h, S)
				draw_colored_polygon(Hex.corners(cc, S * 0.98), Color(0.5, 0.42, 0.35, 0.18))
				_rocks(cc, S, h)
			var pl: Texture2D = UI.tex("res://assets/markers/pianeta.png")
			for h in board.eng.planets:
				var cc := Hex.center(h, S)
				draw_circle(cc, S * 0.95, Color(0.3, 0.55, 0.9, 0.18))
				if pl != null:
					draw_texture_rect(pl, Rect2(cc - Vector2(S, S) * 0.82, Vector2(S, S) * 1.64), false)
				var nm: String = board.eng.sc.get("planet_name", "Pianeta")
				var ww := UI.font_bold.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(S * 0.42)).x
				draw_string(UI.font_bold, cc + Vector2(-ww / 2, S * 1.25), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(S * 0.42), UI.CYAN)

	func _rocks(c: Vector2, S: float, h: Vector2i) -> void:
		var r := RandomNumberGenerator.new()
		r.seed = h.x * 1000 + h.y
		for i in 6:
			var p := c + Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.55, 0.55)) * S
			draw_circle(p, r.randf_range(0.06, 0.16) * S, Color(0.62, 0.58, 0.52, 0.85))

	func _compass(c: Vector2, S: float) -> void:
		var col := Color(1, 1, 1, 0.2)
		for d in 12:
			var v := Hex.dir_vec(d)
			var l := S * (1.9 if d % 2 == 0 else 1.25)
			draw_line(c + v * S * 0.55, c + v * l, col, 3.0 if d % 2 == 0 else 2.0)
			draw_string(UI.font_bold, c + v * S * 0.42 + Vector2(-S * 0.12, S * 0.1), D.DIR_NAMES[d], HORIZONTAL_ALIGNMENT_LEFT, -1, int(S * 0.24), col)


# ================================================================ pedine ed effetti

class UnitLayer extends Node2D:
	var board

	func _draw() -> void:
		UI.init_fonts()
		var S: float = board.S
		var st: Dictionary = board.state
		var units: Dictionary = st.get("units", {})
		var ov: Dictionary = board.ov
		var eng: DVEngine = board.eng
		# evidenziazioni degli esagoni
		for h in ov.get("hl", {}):
			var col: Color = ov["hl"][h]
			var cc := Hex.center(h, S)
			draw_colored_polygon(Hex.corners(cc, S * 0.94), Color(col, 0.28))
			var pts := Hex.corners(cc, S * 0.94)
			pts.append(pts[0])
			draw_polyline(pts, col, 3.0)
		if board.hover.x > -999:
			var pts := Hex.corners(Hex.center(board.hover, S), S)
			pts.append(pts[0])
			draw_polyline(pts, Color(UI.YELLOW, 0.5), 2.0)
		# percorsi previsti
		for pth in ov.get("paths", []):
			var col: Color = pth.get("col", UI.YELLOW)
			var hs: Array = pth["hexes"]
			var prev := Hex.center(pth["from"], S)
			for h in hs:
				var c := Hex.center(h, S)
				draw_line(prev, c, Color(col, 0.7), 3.0)
				draw_circle(c, S * 0.1, col)
				prev = c
			if pth.has("ghost"):
				var g: Dictionary = pth["ghost"]
				var gh: Vector2i = g["hex"]
				_arrow(Hex.center(gh, S), Hex.dir_angle(g["dir"]), S * 0.6, Color(col, 0.85))
		# frecce di lancio
		for ar in ov.get("arrows", []):
			var c := Hex.center(ar[0], S)
			for d in ar[1]:
				var sel: bool = ar.size() > 2 and int(ar[2]) == int(d)
				_arrow(c + Hex.dir_vec(d) * S * 0.25, Hex.dir_angle(d), S * 0.45, UI.YELLOW if sel else Color(UI.CYAN, 0.8))
		# pedine (raggruppate per esagono)
		var stacks := {}
		var order := []
		for id in units:
			var u: Dictionary = units[id]
			if int(u["f"]) & 8:
				continue
			var key: Vector2i = u["h"]
			if not stacks.has(key):
				stacks[key] = []
			stacks[key].append(id)
			order.append(id)
		var prepared := {}
		for id in units:
			if int(units[id]["f"]) & 8:
				var host: String = eng.reg.get(id, {}).get("host", "")
				prepared[host] = prepared.get(host, 0) + 1
		var sel: String = ov.get("sel", "")
		for key in stacks:
			var ids: Array = stacks[key]
			# le astronavi sotto, poi i caccia, poi i missili
			ids.sort_custom(func(a, b): return _rank(eng, a) < _rank(eng, b))
			for i in ids.size():
				var id: String = ids[i]
				var u: Dictionary = units[id]
				var off := Vector2(i, -i) * S * 0.16 if ids.size() > 1 else Vector2.ZERO
				_unit(id, u, u["p"] * S + off, S, id == sel, prepared.get(id, 0))
		# bersagli
		for id in ov.get("targets", {}):
			if not units.has(id):
				continue
			var p: Vector2 = units[id]["p"] * S
			var txt: String = ov["targets"][id]
			draw_arc(p, S * 0.62, 0, TAU, 32, UI.RED, 3.0)
			var fs := int(S * 0.36)
			var w := UI.font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(p + Vector2(-w / 2 - 4, -S * 1.05), Vector2(w + 8, fs + 4)), Color(0, 0, 0, 0.8))
			draw_string(UI.font_bold, p + Vector2(-w / 2, -S * 1.05 + fs - 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.YELLOW)
		# etichette sugli esagoni
		for h in ov.get("labels", {}):
			var c := Hex.center(h, S)
			var txt: String = ov["labels"][h]
			var fs := int(S * 0.34)
			var w := UI.font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(UI.font_bold, c + Vector2(-w / 2, S * 0.75), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.YELLOW)
		# effetti
		for f in st.get("fx", []):
			_fx(f, S)

	static func _rank(eng: DVEngine, id: String) -> int:
		var k: String = eng.reg.get(id, {}).get("kind", "")
		return {"ship": 0, "bc": 1, "mis": 2}.get(k, 3)

	func _unit(id: String, u: Dictionary, p: Vector2, S: float, sel: bool, nprep: int) -> void:
		var eng: DVEngine = board.eng
		var r: Dictionary = eng.reg.get(id, {})
		if r.is_empty():
			return
		var side: int = r["side"]
		var kind: String = r["kind"]
		var f := int(u["f"])
		var hidden: bool = not (f & 1) and not side in board.viewer
		var al: float = u.get("al", 1.0)
		var sz := S * (1.02 if kind == "ship" else 0.8)
		var ffon := (f & 2) != 0
		var t: Texture2D = UI.counter_tex(side, kind, r["cls"], r["label"], hidden or (kind == "ship" and ffon))
		if sel:
			draw_circle(p, sz * 0.86, Color(UI.YELLOW, 0.35 * al))
			draw_arc(p, sz * 0.86, 0, TAU, 40, Color(UI.YELLOW, al), 3.0)
		if ffon:
			draw_circle(p, sz * 0.78, Color(UI.CYAN, 0.18 * al))
			draw_arc(p, sz * 0.78, 0, TAU, 40, Color(UI.CYAN, 0.9 * al), 2.5)
		# ombra
		draw_set_transform(p + Vector2(3, 4), u["a"], Vector2.ONE)
		draw_rect(Rect2(-Vector2(sz, sz) / 2, Vector2(sz, sz)), Color(0, 0, 0, 0.5 * al))
		draw_set_transform(p, u["a"], Vector2.ONE)
		if t != null:
			draw_texture_rect(t, Rect2(-Vector2(sz, sz) / 2, Vector2(sz, sz)), false, Color(1, 1, 1, al))
		else:
			draw_rect(Rect2(-Vector2(sz, sz) / 2, Vector2(sz, sz)), Color(UI.SIDE[side], al))
		draw_rect(Rect2(-Vector2(sz, sz) / 2, Vector2(sz, sz)), Color(0, 0, 0, 0.6 * al), false, 1.5)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# segnalino di velocità (sempre visibile, come da regolamento)
		var vs := S * 0.38
		var vp := p + Vector2(sz * 0.36, sz * 0.36)
		draw_rect(Rect2(vp - Vector2(vs, vs) / 2, Vector2(vs, vs)), Color(0.45, 0.45, 0.47, al))
		draw_rect(Rect2(vp - Vector2(vs, vs) / 2, Vector2(vs, vs)), Color(0.1, 0.1, 0.1, al), false, 1.0)
		var vt := str(u["v"])
		var fs := int(vs * 0.95)
		var w := UI.font_bold.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(UI.font_bold, vp + Vector2(-w / 2, fs * 0.36), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, al))
		if f & 4:
			var jt: Texture2D = UI.tex("res://assets/markers/salto.png")
			if jt != null:
				draw_texture_rect(jt, Rect2(p + Vector2(-sz * 0.62, -sz * 0.62), Vector2(sz, sz) * 0.42), false, Color(1, 1, 1, al))
		if nprep > 0:
			var bp := p + Vector2(-sz * 0.38, sz * 0.36)
			draw_circle(bp, S * 0.17, Color(UI.SIDE_D[side], al))
			var tx := "+%d" % nprep
			var fw := UI.font_bold.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, int(S * 0.24)).x
			draw_string(UI.font_bold, bp + Vector2(-fw / 2, S * 0.08), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, int(S * 0.24), Color(1, 1, 1, al))

	func _arrow(c: Vector2, ang: float, l: float, col: Color) -> void:
		var v := Vector2(cos(ang), sin(ang))
		var n := Vector2(-v.y, v.x)
		var tip := c + v * l * 0.5
		var base := c - v * l * 0.5
		draw_line(base, tip, col, 3.0)
		draw_colored_polygon(PackedVector2Array([tip + v * 4, tip - v * l * 0.3 + n * l * 0.2, tip - v * l * 0.3 - n * l * 0.2]), col)

	func _fx(f: Dictionary, S: float) -> void:
		var t: float = f.get("t", 0.0)
		if t < 0.0 or t > 1.0:
			return
		match f["k"]:
			"beam":
				FX2D.shot(self, f["a"] * S, f["b"] * S, str(f["w"]), bool(f["hit"]), t, S)
			"boom":
				FX2D.boom(self, f["p"] * S, t, S)
			"spark":
				var c: Vector2 = f["p"] * S
				draw_arc(c, S * (0.3 + 0.6 * t), 0, TAU, 24, Color(UI.CYAN, 1.0 - t), 2.0)
			"text":
				FX2D.float_text(self, f["p"] * S, str(f["txt"]), bool(f["bad"]), t, S)
			"warp":
				var c: Vector2 = f["p"] * S
				draw_circle(c, S * (0.2 + 2.0 * t), Color(0.7, 0.85, 1.0, 0.5 * (1.0 - t)))
				draw_line(c - Vector2(S * 3 * t, 0), c + Vector2(S * 3 * t, 0), Color(1, 1, 1, 1.0 - t), 3.0)
			"puff":
				var c: Vector2 = f["p"] * S
				draw_arc(c, S * (0.5 + 0.5 * t), 0, TAU, 24, Color(1, 1, 1, 0.6 * (1.0 - t)), 2.0)
