class_name UI
extends RefCounted
## Helper grafici condivisi. Tema «SPI 1981»: lo spazio nero della mappa con la griglia esagonale
## arancione, il giallo del logo DeltaVee della scatola, il rosa e l'azzurro delle scritte della
## copertina, e le schede bianche dei Spaceship Log stampate in Helvetica condensato.
## Caratteri liberi (OFL): Righteous per i titoli (il lettering tondo anni '70 del logo),
## Saira Condensed per i testi e le tabelle, Share Tech Mono per le letture dei computer di bordo.

const D = preload("res://scripts/data/dv_data.gd")

const SPACE := Color("#08080b")
const SPACE_L := Color("#15141b")
const PANEL := Color("#121118")
const HEX := Color("#e2541b")
const HEX_D := Color("#7a2c0e")
const ORANGE := Color("#f26a21")
const ORANGE_L := Color("#ff9a4a")
const YELLOW := Color("#f4e46a")
const YELLOW_L := Color("#fff4a8")
const PINK := Color("#ef6f9c")
const CYAN := Color("#8fd3f4")
const BLUE := Color("#3a7fc1")
const RED := Color("#e0402a")
const GREEN := Color("#7ed957")
const PAPER := Color("#efe9d8")
const PAPER_D := Color("#d9d0b8")
const INK := Color("#151515")
const TEXT := Color("#ece6d6")
const MUTED := Color("#9b9384")
## colori dei due lati, come le pedine
const SIDE := [Color("#ff6a13"), Color("#7ed321")]
const SIDE_D := [Color("#8a3405"), Color("#3d6f0d")]

static var _tex := {}
static var font_title: Font
static var font_body: Font
static var font_semi: Font
static var font_bold: Font
static var font_mono: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/Righteous-Regular.ttf")
	font_body = load("res://assets/fonts/SairaCondensed-Regular.ttf")
	font_semi = load("res://assets/fonts/SairaCondensed-SemiBold.ttf")
	font_bold = load("res://assets/fonts/SairaCondensed-Bold.ttf")
	font_mono = load("res://assets/fonts/ShareTechMono-Regular.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static var _index: Array = []

## immagine della pedina originale: lato, tipo (ship, bc, ug, g, i, m), sigla; back = retro
static func counter_tex(side: int, kind: String, cls: String, label: String, back := false) -> Texture2D:
	if _index.is_empty():
		var f := FileAccess.open("res://assets/counters/indice.json", FileAccess.READ)
		if f != null:
			_index = JSON.parse_string(f.get_as_text())
	var sf: String = D.SIDE_FILE[side]
	var k := "ship"
	if kind == "bc":
		k = "bc"
	elif kind == "mis":
		k = D.MFILE[cls]
	var name := "%s_%s_%s" % [sf, k, label]
	if not name in _index:
		# stessa pedina con un'altra sigla (le pedine stampate sono finite)
		name = ""
		for n in _index:
			if str(n).begins_with("%s_%s_" % [sf, k]):
				name = n
				break
		if name == "":
			for n in _index:
				if str(n).begins_with("%s_ship_" % sf):
					name = n
					break
	return tex("res://assets/counters/%s%s.png" % [name, "_b" if back else ""])


static func panel_style(bg: Color, border: Color = HEX_D, bw := 2, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


static func dark_style(radius := 8, alpha := 0.94) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), HEX, 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 10
	return sb


## scheda di carta come i Spaceship Log
static func paper_style(radius := 4) -> StyleBoxFlat:
	var sb := panel_style(PAPER, INK, 2, radius)
	sb.set_content_margin_all(10)
	return sb


static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## titolo come il logo della scatola: giallo, tondo, con ombra arancione
static func title(text: String, size := 48, col := YELLOW) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_shadow_color", Color(HEX, 0.85))
	l.add_theme_constant_override("shadow_offset_x", maxi(2, size / 18))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 18))
	return l


static func heading(text: String, size := 24, col := YELLOW) -> Label:
	init_fonts()
	return label(text.to_upper(), size, col, font_bold)


static func mono(text: String, size := 18, col := CYAN) -> Label:
	init_fonts()
	return label(text, size, col, font_mono)


static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 46.0, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func primary(b: Button) -> Button:
	init_fonts()
	b.add_theme_stylebox_override("normal", _btn(HEX, YELLOW))
	b.add_theme_stylebox_override("hover", _btn(ORANGE_L, YELLOW_L))
	b.add_theme_stylebox_override("pressed", _btn(YELLOW, INK))
	b.add_theme_stylebox_override("disabled", _btn(Color("#4a3a32"), Color("#2a221e")))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_font_override("font", font_bold)
	return b


static func _btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 5
	return sb


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_semi
	th.default_font_size = 20
	var sb := _btn(Color("#1d1a20"), HEX_D)
	th.set_stylebox("normal", "Button", sb)
	th.set_stylebox("hover", "Button", _btn(Color("#2c2228"), HEX))
	th.set_stylebox("pressed", "Button", _btn(HEX, YELLOW))
	th.set_stylebox("disabled", "Button", _btn(Color("#141216"), Color("#2a2420")))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", YELLOW_L)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("#5b544a"))
	th.set_font("font", "Button", font_semi)
	th.set_font_size("font_size", "Button", 20)
	th.set_color("font_color", "Label", TEXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_body)
	th.set_font("mono_font", "RichTextLabel", font_mono)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "mono_font_size"]:
		th.set_font_size(k, "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("font", "LineEdit", font_semi)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color("#7a7262"))
	th.set_color("caret_color", "LineEdit", INK)
	th.set_stylebox("normal", "LineEdit", panel_style(PAPER, INK, 2, 4))
	th.set_stylebox("focus", "LineEdit", panel_style(YELLOW_L, HEX, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 18)
	th.set_color("font_color", "TooltipLabel", INK)
	var tp := panel_style(PAPER, INK, 2, 4)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(HEX, 0.9)
	sc.set_corner_radius_all(3)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(k, "VScrollBar", sc)
		th.set_stylebox(k, "HSlider", sc)
	var sct := StyleBoxFlat.new()
	sct.bg_color = Color(1, 1, 1, 0.06)
	th.set_stylebox("scroll", "VScrollBar", sct)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(HEX_D, 0.8)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", sl)
	th.set_stylebox("normal", "OptionButton", sb)
	th.set_stylebox("hover", "OptionButton", _btn(Color("#2c2228"), HEX))
	th.set_stylebox("pressed", "OptionButton", _btn(HEX, YELLOW))
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	th.set_font("font", "OptionButton", font_semi)
	th.set_font_size("font_size", "OptionButton", 19)
	th.set_color("font_color", "OptionButton", TEXT)
	var pm := panel_style(PAPER, INK, 2, 4)
	th.set_stylebox("panel", "PopupMenu", pm)
	th.set_font("font", "PopupMenu", font_semi)
	th.set_font_size("font_size", "PopupMenu", 19)
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", INK)
	var hov := StyleBoxFlat.new()
	hov.bg_color = YELLOW
	th.set_stylebox("hover", "PopupMenu", hov)
	return th


## Sfondo: lo spazio nero con le stelle e una tenue griglia esagonale arancione (disegnato, nessuna immagine).
class Starfield extends Control:
	var stars := []
	var grid := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var r := RandomNumberGenerator.new()
		r.seed = 1981
		for i in 320:
			stars.append([Vector2(r.randf(), r.randf()), r.randf_range(0.5, 2.0), r.randf_range(0.25, 1.0)])
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UI.SPACE)
		if grid:
			var s := 46.0
			var cols := int(size.x / (s * 1.5)) + 2
			var rows := int(size.y / (s * 1.732)) + 2
			for q in cols:
				for rr in rows:
					var c := Hex.center(Vector2i(q, rr), s)
					var pts := Hex.corners(c, s)
					pts.append(pts[0])
					draw_polyline(pts, Color(UI.HEX, 0.07), 1.5)
		for st in stars:
			var p: Vector2 = st[0] * size
			draw_circle(p, st[1], Color(1, 1, 0.92, st[2] * 0.75))
