class_name Hex
extends RefCounted
## Geometria della griglia di DeltaVee: esagoni con il lato piatto in alto (le colonne sono verticali),
## colonne dispari del tabellone (01, 03, …) più in alto, pari più in basso.
## Coordinate globali "a scacchiera" Vector2i(colonna, riga) a partire da 0 (colonna 0 = 01 della
## mappa A); le mappe sono blocchi di 16 × 18 esagoni affiancati.
##
## Direzioni: le ore dell'orologio, 0 = ore 12 … 11 = ore 11. Le ore pari (12, 2, 4, 6, 8, 10)
## puntano a un lato dell'esagono, le dispari a un vertice: lì il movimento è a zig-zag.

const SQ3 := 1.7320508

## spostamenti assiali (q, r) per le sei direzioni verso i lati (indice = ora / 2)
const AX := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]


static func to_ax(h: Vector2i) -> Vector2i:
	return Vector2i(h.x, h.y - (h.x - (h.x & 1)) / 2)


static func from_ax(a: Vector2i) -> Vector2i:
	return Vector2i(a.x, a.y + (a.x - (a.x & 1)) / 2)


static func dist(a: Vector2i, b: Vector2i) -> int:
	var p := to_ax(a)
	var q := to_ax(b)
	var dq := p.x - q.x
	var dr := p.y - q.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## esagono adiacente verso un lato (dir pari)
static func side_step(h: Vector2i, d: int) -> Vector2i:
	d = posmod(d, 12)
	return from_ax(to_ax(h) + AX[d / 2])


static func neighbors(h: Vector2i) -> Array:
	var out := []
	for i in 6:
		out.append(side_step(h, i * 2))
	return out


## Un passo di movimento: per le direzioni verso un vertice si alterna sinistra (zig 0) e destra (zig 1).
## Restituisce [nuovo esagono, nuovo zig].
static func step(h: Vector2i, d: int, zig: int) -> Array:
	d = posmod(d, 12)
	if d % 2 == 0:
		return [side_step(h, d), zig]
	if zig == 0:
		return [side_step(h, d - 1), 1]
	return [side_step(h, d + 1), 0]


## percorso di n passi (escluso l'esagono di partenza); restituisce [esagoni, zig finale]
static func path(h: Vector2i, d: int, zig: int, n: int) -> Array:
	var out := []
	for i in n:
		var s := step(h, d, zig)
		h = s[0]
		zig = s[1]
		out.append(h)
	return [out, zig]


## posizione del centro in pixel (lato = size)
static func center(h: Vector2i, size: float) -> Vector2:
	return Vector2(size * 1.5 * h.x, size * SQ3 * (h.y + 0.5 * (h.x & 1)))


static func corners(c: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(c + Vector2(cos(a), sin(a)) * size)
	return pts


## esagono sotto un punto in pixel
static func at(p: Vector2, size: float) -> Vector2i:
	var qf := (2.0 / 3.0 * p.x) / size
	var rf := (-1.0 / 3.0 * p.x + SQ3 / 3.0 * p.y) / size
	# arrotondamento cubico
	var x := qf
	var z := rf
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return from_ax(Vector2i(int(rx), int(rz)))


## angolo (radianti, 0 = destra) di una direzione dell'orologio
static func dir_angle(d: int) -> float:
	return deg_to_rad(-90.0 + 30.0 * d)


static func dir_vec(d: int) -> Vector2:
	var a := dir_angle(d)
	return Vector2(cos(a), sin(a))


## direzione (0-11) più vicina al vettore da a verso b
static func dir_to(a: Vector2i, b: Vector2i) -> int:
	var v := center(b, 1.0) - center(a, 1.0)
	if v.length() < 0.01:
		return 0
	var ang := rad_to_deg(atan2(v.y, v.x)) + 90.0
	return posmod(int(roundf(ang / 30.0)), 12)


## differenza fra due direzioni, da -5 a +6
static func ddiff(a: int, b: int) -> int:
	var d := posmod(b - a, 12)
	return d - 12 if d > 6 else d


# ------------------------------------------------------------------ sigle delle mappe

## "A0207" -> esagono globale, date le mappe dello scenario (lettere da sinistra a destra)
static func parse(code: String, maps: Array) -> Vector2i:
	var mi := maps.find(code.substr(0, 1))
	if mi < 0:
		mi = "ABCDE".find(code.substr(0, 1))
	var col := int(code.substr(1, 2)) - 1
	var row := int(code.substr(3, 2)) - 1
	return Vector2i(mi * 16 + col, row)


## blocco di mappa che contiene l'esagono
static func block(h: Vector2i) -> Vector2i:
	return Vector2i(floori(h.x / 16.0), floori(h.y / 18.0))


## sigla dell'esagono come sul tabellone (lettera della mappa + colonna + riga)
static func code(h: Vector2i, letters := {}) -> String:
	var b := block(h)
	var col := h.x - b.x * 16 + 1
	var row := h.y - b.y * 18 + 1
	var key := "%d,%d" % [b.x, b.y]
	var L: String = letters.get(key, "?")
	return "%s%02d%02d" % [L, col, row]
