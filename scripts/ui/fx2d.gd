class_name FX2D
extends RefCounted
## Effetti grafici in 2D, diversi per ogni tipo di fuoco della tabella [8.6]:
## - raffica laser: un singolo dardo rosso veloce;
## - sbarramento laser: una scarica di cinque dardi rosso-arancio a ventaglio stretto;
## - raffica di particelle: un globo di plasma azzurro, più lento, con la scia e le scintille elettriche;
## - sbarramento di particelle: tre globi bianco-azzurri che convergono sul bersaglio, legati da fulmini.
## Esplosioni con lampo, palla di fuoco, onda d'urto, detriti e fumo.

const LASER := Color("#ff3b2f")
const LASER2 := Color("#ff9a3a")
const PLASMA := Color("#5fd8ff")
const PLASMA2 := Color("#c9a6ff")


## parametri del tipo di fuoco: [numero di colpi, ritardo fra i colpi, durata del volo]
static func pattern(w: String) -> Array:
	match w:
		"lbb":
			return [5, 0.07, 0.26]
		"pb":
			return [1, 0.0, 0.5]
		"pbb":
			return [3, 0.04, 0.55]
	return [1, 0.0, 0.32]


static func _rng(a: Vector2, b: Vector2) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(a.x * 13.0 + a.y * 7.0 + b.x * 3.0 + b.y)
	return r


static func shot(ci: CanvasItem, a: Vector2, b: Vector2, w: String, hit: bool, t: float, S: float) -> void:
	var d := b - a
	if d.length() < 1.0:
		d = Vector2(1, 0)
	var dir := d.normalized()
	var nrm := dir.orthogonal()
	var end := b if hit else b + nrm * S * 0.8 + dir * S * 1.6
	var pt := pattern(w)
	var n: int = pt[0]
	var particle := w.begins_with("p")
	var col := PLASMA if particle else LASER
	# lampo alla bocca da fuoco
	if t < 0.14 + float(pt[1]) * n:
		var k: float = 1.0 - t / (0.14 + float(pt[1]) * n)
		ci.draw_circle(a + dir * S * 0.45, S * (0.18 + 0.12 * k), Color(col, 0.7 * k))
		ci.draw_circle(a + dir * S * 0.45, S * 0.08, Color(1, 1, 1, k))
	var arrive := 0.0
	for i in n:
		var t0: float = i * pt[1]
		var dur: float = pt[2]
		var k: float = (t - t0) / dur
		arrive = maxf(arrive, t0 + dur)
		if k < 0.0:
			continue
		var head := Vector2.ZERO
		var lat := 0.0
		match w:
			"lbb":
				lat = (float(i) - 2.0) * 0.06 * S
			"pbb":
				lat = (float(i) - 1.0) * 0.9 * S
		if k <= 1.0:
			# traiettoria: dritta per i laser, arcuata (che converge) per lo sbarramento di particelle
			var bend := lat * 4.0 * k * (1.0 - k) if w == "pbb" else lat
			head = a.lerp(end, k) + nrm * bend
			if particle:
				_orb(ci, head, dir, S, w == "pbb", t, i)
			else:
				var tail := head - dir * S * (0.9 if w == "lb" else 0.6)
				if (tail - a).dot(dir) < 0:
					tail = a
				var c2 := LASER if (w == "lb" or i % 2 == 0) else LASER2
				ci.draw_line(tail, head, Color(c2, 0.28), S * 0.22)
				ci.draw_line(tail, head, Color(c2, 0.85), S * 0.09)
				ci.draw_line(tail.lerp(head, 0.3), head, Color(1, 1, 0.92), S * 0.035)
				ci.draw_circle(head, S * 0.07, Color(1, 1, 1, 0.95))
		elif not hit and k <= 1.3:
			# il colpo mancato si perde nello spazio
			var fade := 1.0 - (k - 1.0) / 0.3
			ci.draw_circle(end + dir * S * (k - 1.0) * 2.0, S * 0.08, Color(col, fade))
	# fulmini dello sbarramento di particelle
	if w == "pbb" and t < arrive:
		var r := RandomNumberGenerator.new()
		r.seed = int(t * 40.0)
		var k: float = clampf(t / arrive, 0.0, 1.0)
		var tip := a.lerp(end, k)
		var prev := a
		for j in 9:
			var q := a.lerp(tip, float(j + 1) / 9.0) + nrm * r.randf_range(-0.25, 0.25) * S
			ci.draw_line(prev, q, Color(PLASMA2, 0.75), 2.0)
			prev = q
	# colpo mancato: la scritta sul bersaglio
	if not hit and t > arrive:
		float_text(ci, b, "mancato", false, clampf((t - arrive) / maxf(0.01, 1.0 - arrive), 0.0, 1.0), S, Color(0.75, 0.8, 0.9))
	# impatto
	if hit and t >= arrive * 0.95:
		var k := clampf((t - arrive) / maxf(0.01, 1.0 - arrive), 0.0, 1.0)
		impact(ci, b, dir, w, k, S)


static func _orb(ci: CanvasItem, p: Vector2, dir: Vector2, S: float, big: bool, t: float, i: int) -> void:
	var r := S * (0.24 if big else 0.2)
	var pulse := 1.0 + 0.15 * sin(t * 60.0 + i)
	for j in 7:
		var q := p - dir * S * 0.13 * (j + 1)
		ci.draw_circle(q, r * (0.75 - j * 0.09), Color(PLASMA, 0.32 - j * 0.04))
	ci.draw_circle(p, r * 1.6 * pulse, Color(PLASMA2, 0.22))
	ci.draw_circle(p, r * pulse, Color(PLASMA, 0.85))
	ci.draw_circle(p, r * 0.45, Color(1, 1, 1))
	var rr := RandomNumberGenerator.new()
	rr.seed = int(t * 50.0) + i * 17
	for k in 3:
		var ang := rr.randf() * TAU
		var p1 := p + Vector2(cos(ang), sin(ang)) * r * 1.1
		var p2 := p1 + Vector2(cos(ang + 0.6), sin(ang + 0.6)) * r * 0.9
		ci.draw_line(p1, p2, Color(1, 1, 1, 0.8), 1.5)


static func impact(ci: CanvasItem, c: Vector2, dir: Vector2, w: String, k: float, S: float) -> void:
	var particle := w.begins_with("p")
	var big := w.ends_with("bb")
	var col := PLASMA if particle else LASER2
	var r := _rng(c, dir * 100.0)
	ci.draw_circle(c, S * (0.25 + 0.5 * k) * (1.3 if big else 1.0), Color(1, 1, 0.9, 0.85 * (1.0 - k)))
	ci.draw_circle(c, S * (0.4 + 0.9 * k) * (1.3 if big else 1.0), Color(col, 0.35 * (1.0 - k)))
	if particle:
		ci.draw_arc(c, S * (0.3 + 1.4 * k), 0, TAU, 32, Color(PLASMA2, 1.0 - k), 3.0 * (1.0 - k) + 1.0)
	var nsp := 16 if big else 10
	for i in nsp:
		# le scintille schizzano soprattutto in avanti, nella direzione del colpo
		var ang := dir.angle() + r.randf_range(-1.6, 1.6)
		var sp := r.randf_range(0.6, 1.4)
		var v := Vector2(cos(ang), sin(ang))
		var p0 := c + v * S * sp * 1.2 * k
		ci.draw_line(p0, p0 + v * S * 0.18 * (1.0 - k), Color(UI.YELLOW_L if not particle else Color.WHITE, 1.0 - k), 2.0)


static func boom(ci: CanvasItem, c: Vector2, t: float, S: float) -> void:
	var r := _rng(c, Vector2(7, 3))
	# lampo
	if t < 0.22:
		ci.draw_circle(c, S * (0.5 + 3.0 * t), Color(1, 1, 1, 1.0 - t / 0.22))
	# onda d'urto
	ci.draw_arc(c, S * (0.3 + 2.6 * t), 0, TAU, 48, Color(1.0, 0.85, 0.6, 0.8 * (1.0 - t)), maxf(1.0, 5.0 * (1.0 - t)))
	# fumo
	if t > 0.35:
		for i in 6:
			var off := Vector2(r.randf_range(-1, 1), r.randf_range(-1, 1)) * S * 0.6 * t
			ci.draw_circle(c + off, S * (0.4 + 0.7 * t) * r.randf_range(0.7, 1.1), Color(0.35, 0.33, 0.32, 0.22 * (1.0 - t)))
	# palla di fuoco
	var fc: Color
	if t < 0.3:
		fc = Color("#fff3a0").lerp(Color("#ffb030"), t / 0.3)
	elif t < 0.6:
		fc = Color("#ffb030").lerp(Color("#e0402a"), (t - 0.3) / 0.3)
	else:
		fc = Color("#e0402a").lerp(Color("#3a2a28"), (t - 0.6) / 0.4)
	for i in 8:
		var off := Vector2(r.randf_range(-1, 1), r.randf_range(-1, 1)) * S * 0.45 * sqrt(t)
		var rad := S * (0.22 + 0.6 * sqrt(t)) * r.randf_range(0.6, 1.1)
		ci.draw_circle(c + off, rad, Color(fc, 0.75 * pow(1.0 - t, 1.2)))
	ci.draw_circle(c, S * 0.3 * (1.0 - t), Color(1, 1, 0.85, 1.0 - t))
	# detriti
	for i in 18:
		var ang := r.randf() * TAU
		var sp := r.randf_range(0.8, 2.4)
		var v := Vector2(cos(ang), sin(ang))
		var dist := S * sp * (1.0 - pow(1.0 - t, 2.0))
		var p0 := c + v * dist
		var col := Color("#ffd27a").lerp(Color("#c0402a"), t)
		ci.draw_line(p0, p0 + v * S * 0.16, Color(col, 1.0 - t), 2.5 if i % 3 == 0 else 1.5)


## scritta che sale e sfuma sopra un bersaglio (esito del colpo)
static func float_text(ci: CanvasItem, p: Vector2, txt: String, bad: bool, t: float, S: float, col := Color(0, 0, 0, 0)) -> void:
	if txt == "":
		return
	UI.init_fonts()
	if col.a == 0.0:
		col = UI.RED if bad else UI.YELLOW
	var fs := int(S * (0.5 if bad else 0.4))
	var al := clampf(minf(t / 0.12, (1.0 - t) / 0.3), 0.0, 1.0)
	var pos := p + Vector2(0, -S * (0.9 + 0.7 * t))
	var w := UI.font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(UI.font_bold, pos - Vector2(w / 2, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85 * al))
	ci.draw_string(UI.font_bold, pos - Vector2(w / 2, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, al))
