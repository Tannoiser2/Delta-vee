class_name Trail
extends RefCounted
## Scie di astronavi, caccia e missili: le posizioni recenti di ogni unità (in lati di esagono), che si
## spengono dopo LIFE secondi. Un salto lungo (replay riavvolto, uscita dall'hangar) fa ripartire la scia.

const LIFE := 3.0
const JUMP := 2.5                # salto oltre il quale la scia riparte (in lati di esagono)

var pts := {}                    # id -> [[tempo, Vector2], ...]


func update(units: Dictionary, eng: DVEngine) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id in units:
		var u: Dictionary = units[id]
		var f := int(u.get("f", 0))
		if f & 8 or float(u.get("al", 1.0)) < 0.05:
			continue
		var p: Vector2 = u["p"]
		if not pts.has(id):
			pts[id] = [[now, p]]
			continue
		var arr: Array = pts[id]
		var last: Vector2 = arr[-1][1]
		var d := p.distance_to(last)
		if d > JUMP:
			pts[id] = [[now, p]]
		elif d > 0.03:
			arr.append([now, p])
	prune(now)


func prune(now: float) -> void:
	for id in pts.keys():
		var arr: Array = pts[id]
		while arr.size() > 1 and now - float(arr[0][0]) > LIFE:
			arr.pop_front()
		if arr.size() <= 1 and now - float(arr[-1][0]) > LIFE:
			pts.erase(id)


func active() -> bool:
	for id in pts:
		if pts[id].size() > 1:
			return true
	return false


func kind(id: String, eng: DVEngine) -> String:
	if eng == null or not eng.reg.has(id):
		return "ship"
	return str(eng.reg[id]["kind"])


func color(id: String, eng: DVEngine) -> Color:
	if eng == null or not eng.reg.has(id):
		return Color.WHITE
	var r: Dictionary = eng.reg[id]
	if r["kind"] == "mis":
		return Color(1.0, 0.72, 0.38)
	return UI.SIDE[int(r["side"])].lightened(0.25)
