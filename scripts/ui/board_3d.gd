extends SubViewportContainer
## Il tabellone in 3D: le mappe esagonali stese nello spazio stellato, le pedine originali come
## gettoni spessi e sopra ciascuna un modellino d'epoca (scafo bianco con le strisce del lato),
## i missili, i pianeti e i campi di asteroidi. Si ruota trascinando, si sposta col tasto destro
## (o Maiusc + trascina), si ingrandisce con la rotella. Le pedine coperte restano un segnale anonimo.

signal hex_clicked(h: Vector2i)
signal hex_hovered(h: Vector2i)

const D = preload("res://scripts/data/dv_data.gd")
const BW := 24.0                 # larghezza di un blocco di mappa (lato esagono = 1)
const BH := 31.17691             # altezza: 18 × radice di 3

var eng: DVEngine
var state := {"units": {}, "fx": [], "maps": {}}
var viewer: Array = [0, 1]
var ov := {}
var vp: SubViewport
var root3: Node3D
var cam: Camera3D
var target := Vector3(20, 0, 14)
var yaw := 0.0
var pitch := 0.95
var dist := 38.0
var _drag := 0
var _from := Vector2.ZERO
var _moved := false
var _maps_key := ""
var _map_nodes := {}
var _tile_tex: Texture2D
var _units := {}                 # id -> {node, token, model, vel, key}
var _ov_mesh: MeshInstance3D
var _fx_root: Node3D
var _ov_dirty := true
var hover := Vector2i(-999, -999)
var _static_done := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.handle_input_locally = false
	vp.own_world_3d = true
	add_child(vp)
	root3 = Node3D.new()
	vp.add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = _star_panorama()
	sky.sky_material = pm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.62)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.88)
	root3.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.75, 1.0)
	root3.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 45
	cam.far = 800
	root3.add_child(cam)
	_ov_mesh = MeshInstance3D.new()
	_ov_mesh.mesh = ImmediateMesh.new()
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.vertex_color_use_as_albedo = true
	om.cull_mode = BaseMaterial3D.CULL_DISABLED
	om.no_depth_test = false
	_ov_mesh.material_override = om
	root3.add_child(_ov_mesh)
	_fx_root = Node3D.new()
	root3.add_child(_fx_root)
	_tile_tex = _make_tile()
	_update_cam()


func set_engine(e: DVEngine) -> void:
	eng = e


func set_state(st: Dictionary) -> void:
	state = st
	if not is_visible_in_tree():
		return
	var mk := str(st.get("maps", {}).keys())
	if mk != _maps_key:
		_maps_key = mk
		_build_maps()
	if not _static_done and eng != null:
		_static_done = true
		_build_static()
	_sync_units()
	_ov_dirty = true


func redraw() -> void:
	_ov_dirty = true


func _process(_d: float) -> void:
	if not is_visible_in_tree():
		return
	if _ov_dirty or not state.get("fx", []).is_empty():
		_ov_dirty = false
		_draw_overlay()
		_draw_fx()


# ---------------------------------------------------------------- camera

func _update_cam() -> void:
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func fit(all_maps := false) -> void:
	var r := _bounds()
	var ub := _units_bounds() if not all_maps else Rect2()
	if ub.size.x > 0:
		r = ub
	target = Vector3(r.get_center().x, 0, r.get_center().y)
	dist = clampf(maxf(r.size.x, r.size.y) * 0.95, 12.0, 160.0)
	yaw = 0.0
	pitch = 0.95
	_update_cam()


func _units_bounds() -> Rect2:
	if eng == null:
		return Rect2()
	var r := Rect2()
	var first := true
	for id in eng.order:
		var u: Dictionary = eng.units[id]
		if u["st"] != "on":
			continue
		var p := Hex.center(u["hex"], 1.0)
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	if first:
		return Rect2()
	r = r.grow(4.0)
	if r.size.x < 22:
		r = r.grow_individual((22 - r.size.x) / 2, 0, (22 - r.size.x) / 2, 0)
	return r


func center_on(p: Vector2) -> void:
	target = Vector3(p.x, 0, p.y)
	_update_cam()


func _bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for key in _maps():
		var p: PackedStringArray = str(key).split(",")
		var rr := Rect2(Vector2(int(p[0]) * BW - 0.75, int(p[1]) * BH - 0.87), Vector2(BW, BH))
		r = rr if first else r.merge(rr)
		first = false
	return r


func _maps() -> Dictionary:
	var m: Dictionary = state.get("maps", {})
	if m.is_empty() and eng != null:
		m = eng.maps
	return m


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			dist = clampf(dist / 1.12, 4.0, 220.0)
			_update_cam()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			dist = clampf(dist * 1.12, 4.0, 220.0)
			_update_cam()
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				_drag = ev.button_index
				if ev.button_index == MOUSE_BUTTON_LEFT and ev.shift_pressed:
					_drag = MOUSE_BUTTON_RIGHT
				_from = ev.position
				_moved = false
			else:
				if _drag == MOUSE_BUTTON_LEFT and not _moved:
					var h = _pick(ev.position)
					if h != null:
						hex_clicked.emit(h)
				_drag = 0
	elif ev is InputEventMouseMotion:
		if _drag != 0:
			if (ev.position - _from).length() > 6:
				_moved = true
			if _moved:
				if _drag == MOUSE_BUTTON_LEFT:
					yaw -= ev.relative.x * 0.006
					pitch = clampf(pitch + ev.relative.y * 0.005, 0.25, 1.52)
				else:
					var right := cam.global_transform.basis.x
					var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
					target += (-right * ev.relative.x + fwd * ev.relative.y) * dist * 0.0016
				_update_cam()
		else:
			var h = _pick(ev.position)
			if h != null and h != hover:
				hover = h
				hex_hovered.emit(h)
				_ov_dirty = true
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / ev.factor, 4.0, 220.0)
		_update_cam()


func _pick(p: Vector2):
	var sc := Vector2(vp.size) / size if size.x > 0 else Vector2.ONE
	var pp := p * sc
	var o := cam.project_ray_origin(pp)
	var d := cam.project_ray_normal(pp)
	if absf(d.y) < 0.0001:
		return null
	var t := -o.y / d.y
	if t < 0:
		return null
	var w := o + d * t
	return Hex.at(Vector2(w.x, w.z), 1.0)


# ---------------------------------------------------------------- mappe

func _star_panorama() -> Texture2D:
	var img := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(0.012, 0.012, 0.02))
	var r := RandomNumberGenerator.new()
	r.seed = 1981
	for i in 2600:
		var x := r.randi_range(0, 2047)
		var y := r.randi_range(0, 1023)
		var b := r.randf_range(0.25, 1.0)
		var c := Color(b, b, b * r.randf_range(0.85, 1.0))
		img.set_pixel(x, y, c)
		if b > 0.9:
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + dd
				if q.x >= 0 and q.x < 2048 and q.y >= 0 and q.y < 1024:
					img.set_pixel(q.x, q.y, c * 0.5)
	# una nebulosa rosata come sulla copertina
	for i in 900:
		var x := int(1400 + r.randfn(0, 180))
		var y := int(380 + r.randfn(0, 90))
		if x >= 0 and x < 2048 and y >= 0 and y < 1024:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, c + Color(0.05, 0.015, 0.035))
	return ImageTexture.create_from_image(img)


## un blocco di mappa disegnato una volta in una texture periodica (le mappe sono tutte uguali)
func _make_tile() -> Texture2D:
	var tv := SubViewport.new()
	var px := 1536
	tv.size = Vector2i(px, int(px * BH / BW))
	tv.transparent_bg = false
	tv.render_target_update_mode = SubViewport.UPDATE_ONCE
	tv.disable_3d = true
	vp.add_child(tv)
	var n := TileDraw.new()
	n.k = px / BW
	tv.add_child(n)
	return tv.get_texture()


class TileDraw extends Node2D:
	var k := 64.0

	func _draw() -> void:
		UI.init_fonts()
		var w := 24.0 * k
		var h := 31.17691 * k
		draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.02, 0.025))
		var o := Vector2(0.75, 0.866) * k
		var col := Color(UI.HEX, 0.95)
		for q in range(-1, 17):
			for r in range(-1, 19):
				var hh := Vector2i(q, r)
				var c := Hex.center(hh, k) + o
				var pts := Hex.corners(c, k)
				pts.append(pts[0])
				draw_polyline(pts, col, 3.0)
				var qq := posmod(q, 16)
				var rr := posmod(r, 18)
				draw_string(UI.font_mono, c + Vector2(-k * 0.42, -k * 0.48), "%02d%02d" % [qq + 1, rr + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, int(k * 0.3), col)
		var cc := Hex.center(Vector2i(8, 8), k) + o
		var logo := "DeltaVee"
		var fs := int(k * 2.1)
		var lw := UI.font_title.get_string_size(logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(UI.font_title, cc + Vector2(-lw / 2, -k * 1.6), logo, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.83, 0.8, 0.16))
		for d in 12:
			var v := Hex.dir_vec(d)
			var c2 := cc + Vector2(0, k * 1.2)
			draw_line(c2 + v * k * 0.55, c2 + v * k * (1.9 if d % 2 == 0 else 1.25), Color(1, 1, 1, 0.45), 4.0 if d % 2 == 0 else 2.5)


func _build_maps() -> void:
	for k in _map_nodes:
		_map_nodes[k].queue_free()
	_map_nodes = {}
	var mp := _maps()
	for key in mp:
		var p: PackedStringArray = str(key).split(",")
		var bx := int(p[0])
		var by := int(p[1])
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(BW, BH)
		mi.mesh = pl
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tile_tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mi.material_override = m
		mi.position = Vector3(bx * BW - 0.75 + BW / 2, -0.02, by * BH - 0.866 + BH / 2)
		root3.add_child(mi)
		var lb := Label3D.new()
		lb.text = str(mp[key])
		lb.font = UI.font_title
		lb.font_size = 256
		lb.pixel_size = 0.012
		lb.modulate = Color(UI.YELLOW, 0.22)
		lb.outline_size = 0
		lb.rotation_degrees = Vector3(-90, 0, 0)
		mi.add_child(lb)
		lb.position = Vector3(-BW / 2 + 2.3, 0.02, -BH / 2 + 3.2)
		_map_nodes[key] = mi


func _build_static() -> void:
	for h in eng.planets:
		var c := Hex.center(h, 1.0)
		var sp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.75
		sm.height = 1.5
		sp.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = UI.tex("res://assets/markers/pianeta.png")
		mat.uv1_scale = Vector3(1.6, 1, 1)
		mat.albedo_color = Color(0.75, 0.85, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.2, 0.4)
		sp.material_override = mat
		sp.position = Vector3(c.x, 0.9, c.y)
		root3.add_child(sp)
		var atm := MeshInstance3D.new()
		var am := SphereMesh.new()
		am.radius = 0.86
		am.height = 1.72
		atm.mesh = am
		var amat := StandardMaterial3D.new()
		amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		amat.albedo_color = Color(0.4, 0.7, 1.0, 0.18)
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		atm.material_override = amat
		sp.add_child(atm)
		var lb := Label3D.new()
		lb.text = eng.sc.get("planet_name", "")
		lb.font = UI.font_bold
		lb.font_size = 64
		lb.pixel_size = 0.01
		lb.modulate = UI.CYAN
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position = Vector3(0, 1.2, 0)
		sp.add_child(lb)
	var rr := RandomNumberGenerator.new()
	rr.seed = 7
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.55, 0.5, 0.45)
	rock.roughness = 1.0
	for h in eng.asteroids:
		var c := Hex.center(h, 1.0)
		for i in 5:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var rad := rr.randf_range(0.07, 0.2)
			sm.radius = rad
			sm.height = rad * 2
			sm.radial_segments = 6
			sm.rings = 3
			mi.mesh = sm
			mi.material_override = rock
			mi.scale = Vector3(1.0, rr.randf_range(0.6, 1.0), rr.randf_range(0.7, 1.3))
			mi.rotation = Vector3(rr.randf() * 3, rr.randf() * 3, rr.randf() * 3)
			mi.position = Vector3(c.x + rr.randf_range(-0.6, 0.6), rr.randf_range(0.2, 0.9), c.y + rr.randf_range(-0.55, 0.55))
			root3.add_child(mi)


# ---------------------------------------------------------------- pedine e modellini

func _mat(col: Color, metal := 0.3, rough := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


# ---------------------------------------------------------------- modelli 3D (Meshy)

## modelli: file, rotazione per portare la prua a +x, ugelli dei motori [z, y, raggio] nel modello
## ruotato (misurati dalla vista di poppa)
const MODELS := {
	"TX": {"rot": 180.0, "noz": [[0.0, 0.05, 0.05], [-0.3, 0.0, 0.06], [0.3, -0.02, 0.06]]},
	"Piccolo": {"rot": 90.0, "noz": [[0.0, 0.005, 0.08], [-0.18, 0.0, 0.05], [0.18, 0.0, 0.05]]},
	"Dagger": {"rot": 180.0, "noz": [[0.0, 0.07, 0.05], [-0.1, -0.03, 0.03], [0.1, -0.03, 0.03]]},
	"Gamma": {"rot": 180.0, "noz": [[-0.08, 0.2, 0.06], [0.1, 0.2, 0.06], [-0.05, -0.08, 0.05], [0.07, -0.08, 0.05]]},
	"Flute": {"rot": 180.0, "noz": [[-0.12, 0.1, 0.06], [0.12, 0.1, 0.06], [-0.12, -0.08, 0.05], [0.12, -0.08, 0.05]]},
	"Sword": {"rot": 180.0, "noz": [[0.0, 0.03, 0.05], [-0.4, -0.1, 0.05], [0.4, -0.1, 0.05]]},
	"Zeta": {"rot": 180.0, "noz": [[0.0, 0.0, 0.1]]},
	"Clarinet": {"rot": 180.0, "noz": [[-0.03, 0.03, 0.03], [0.03, 0.03, 0.03], [-0.03, -0.03, 0.03], [0.03, -0.03, 0.03]]},
	"Spear": {"rot": 180.0, "noz": [[0.0, 0.0, 0.04], [-0.42, 0.0, 0.05], [0.42, 0.0, 0.05]]},
	"Iota": {"rot": 180.0, "noz": [[0.0, -0.02, 0.08], [-0.04, -0.2, 0.04], [0.04, -0.2, 0.04]]},
	"Mu": {"rot": 180.0, "noz": [[-0.05, 0.05, 0.045], [0.05, 0.05, 0.045], [-0.05, -0.12, 0.045], [0.05, -0.12, 0.045]]},
	"missile": {"rot": 180.0, "noz": [[0.0, 0.0, 0.06]]},
}

static var _scenes := {}
static var _sh_hull: Shader
static var _sh_flame: Shader

const HULL_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 accent : source_color = vec3(1.0, 0.0, 0.0);
uniform float accent_on = 0.0;
uniform vec3 hull_tint : source_color = vec3(1.0);
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / (mx + 0.0001);
	// strisce rosse -> colore del lato
	float red = clamp((c.r - max(c.g, c.b)) * 4.0 - 0.1, 0.0, 1.0) * smoothstep(0.2, 0.38, sat) * accent_on;
	c = mix(c, accent * (mx * 1.05), red);
	// scafo chiaro e poco saturo -> tinta del lato
	float hull = (1.0 - smoothstep(0.08, 0.3, sat)) * smoothstep(0.3, 0.75, mx);
	c = mix(c, c * hull_tint, hull);
	ALBEDO = c;
	ROUGHNESS = 0.5;
	METALLIC = 0.3;
	SPECULAR = 0.5;
}
"""

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 core : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 outer : source_color = vec3(0.35, 0.6, 1.0);
uniform float power = 1.0;
varying float k;
void vertex() {
	k = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}
void fragment() {
	float f = abs(dot(NORMAL, VIEW));
	float flick = 0.85 + 0.15 * sin(TIME * 40.0 + k * 12.0);
	vec3 col = mix(outer, core, pow(k, 2.5));
	ALBEDO = col * pow(k, 1.6) * pow(f, 3.0) * power * flick;
}
"""


static func model_key(kind: String, cls: String) -> String:
	if kind == "mis":
		return "missile"
	if kind == "bc" or cls in ["T5000", "TX"]:
		return "TX"
	return cls if MODELS.has(cls) else "Piccolo"


## lunghezza in esagoni (lato = 1): dalla più piccola (Terwillicker, 0 moduli) al Corco Mu (12)
static func model_len(kind: String, cls: String) -> float:
	match kind:
		"mis":
			return 0.5
		"bc":
			return 0.45
	return 0.65 + 0.1 * int(D.SHIPS.get(cls, {}).get("pods", 4))


static func _aabb_of(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var b: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = b if acc[0] == null else (acc[0] as AABB).merge(b)
	for c in n.get_children():
		_aabb_of(c, t, acc)


func _recolor(n: Node, side: int) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
			var m := ShaderMaterial.new()
			m.shader = _sh_hull
			m.set_shader_parameter("albedo_tex", tex)
			if side == 1:
				# l'altra squadra: strisce verdi e scafo grigio-verde
				m.set_shader_parameter("accent", UI.SIDE[1])
				m.set_shader_parameter("accent_on", 1.0)
				m.set_shader_parameter("hull_tint", Color(0.74, 0.86, 0.72))
			mi.set_surface_override_material(i, m)
	for c in n.get_children():
		_recolor(c, side)


## modellino 3D: prua verso +x, lunghezza secondo la stazza; i getti dei motori in meta "flames"
func _model(kind: String, cls: String, side: int) -> Node3D:
	if _sh_hull == null:
		_sh_hull = Shader.new()
		_sh_hull.code = HULL_SHADER
		_sh_flame = Shader.new()
		_sh_flame.code = FLAME_SHADER
	var key := model_key(kind, cls)
	if not _scenes.has(key):
		_scenes[key] = load("res://assets/models/%s.glb" % key)
	var def: Dictionary = MODELS[key]
	var n := Node3D.new()
	var body := Node3D.new()
	n.add_child(body)
	var inst: Node3D = (_scenes[key] as PackedScene).instantiate()
	inst.rotation_degrees.y = def["rot"]
	body.add_child(inst)
	var acc := [null]
	_aabb_of(inst, Transform3D.IDENTITY, acc)
	var bb: AABB = acc[0]
	var sc := model_len(kind, cls) / maxf(0.001, bb.size.x)
	var ctr := bb.get_center()
	body.scale = Vector3.ONE * sc
	body.position = -ctr * sc
	_recolor(inst, side)
	# getti: un cono additivo dietro ogni ugello
	var flames := []
	for nz in def["noz"]:
		var fl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(nz[2]) * sc
		cm.bottom_radius = 0.0
		cm.height = 1.0
		cm.radial_segments = 14
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		fl.mesh = cm
		var fm := ShaderMaterial.new()
		fm.shader = _sh_flame
		if kind == "mis":
			fm.set_shader_parameter("outer", Color(1.0, 0.45, 0.12))
		fl.material_override = fm
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.rotation_degrees.z = -90.0
		var base := Vector3(bb.position.x, float(nz[1]), float(nz[0]))
		var pos := (base - ctr) * sc
		n.add_child(fl)
		flames.append({"node": fl, "x": pos.x, "pos": pos, "r": float(nz[2]) * sc})
	n.set_meta("flames", flames)
	return n


## lunghezza dei getti: cresce con la velocità e con la potenza dei motori (manovra della nave)
func _set_flames(m: Node3D, kind: String, cls: String, v: int, on: bool) -> void:
	var mr := 9.0 if kind != "ship" else float(D.SHIPS.get(cls, {}).get("mr", 6))
	var ln := clampf((0.12 + 0.06 * v) * (0.6 + 0.06 * mr), 0.08, 1.1) if on else 0.0
	if kind == "mis":
		ln = clampf(0.1 + 0.025 * v, 0.1, 0.45)
	for f in m.get_meta("flames", []):
		var fl: MeshInstance3D = f["node"]
		fl.visible = ln > 0.0
		var w := 1.0 + 0.03 * v
		fl.scale = Vector3(w, ln, w)
		fl.position = f["pos"] - Vector3(ln * 0.5, 0, 0)


func _sync_units() -> void:
	var units: Dictionary = state.get("units", {})
	for id in _units.keys():
		if not units.has(id):
			_units[id]["node"].queue_free()
			_units.erase(id)
	# pile: le pedine nello stesso esagono si sovrappongono un po' più in alto
	var stacks := {}
	for id in units:
		var u: Dictionary = units[id]
		if int(u["f"]) & 8:
			continue
		var k: Vector2i = u["h"]
		stacks[k] = stacks.get(k, 0) + 1
	var seen := {}
	for id in units:
		var u: Dictionary = units[id]
		var r: Dictionary = eng.reg.get(id, {})
		if r.is_empty():
			continue
		var f := int(u["f"])
		var side: int = r["side"]
		var hidden: bool = not (f & 1) and not side in viewer
		var key := "%s|%s|%s" % [hidden, (f & 2) != 0, (f & 8) != 0]
		var e: Dictionary = _units.get(id, {})
		if e.is_empty() or e["key"] != key:
			if not e.is_empty():
				e["node"].queue_free()
			e = _make_unit(id, r, hidden, (f & 2) != 0, (f & 8) != 0)
			e["key"] = key
			_units[id] = e
		var node: Node3D = e["node"]
		var hk: Vector2i = u["h"]
		var idx: int = seen.get(hk, 0)
		if not (f & 8):
			seen[hk] = idx + 1
		var lift := idx * 0.1
		var p: Vector2 = u["p"]
		var off := Vector2(idx, -idx) * 0.12 if stacks.get(hk, 1) > 1 else Vector2.ZERO
		if f & 8:
			off = Vector2(-0.3, 0.3)
			lift = 0.16
		node.position = Vector3(p.x + off.x, lift, p.y + off.y)
		node.rotation = Vector3(0, -float(u["a"]), 0)
		var al: float = u.get("al", 1.0)
		node.visible = al > 0.05
		if e.has("model") and e["model"] != null:
			e["model"].scale = Vector3.ONE * clampf(al, 0.05, 1.0) * float(e["model"].get_meta("base", 1.0))
			var eng_on := true
			if eng != null and eng.units.has(id) and r["kind"] != "mis":
				eng_on = eng.part_state(eng.units[id], "engine") < 3 and eng.units[id]["st"] != "dead"
			_set_flames(e["model"], r["kind"], r["cls"], int(u["v"]), eng_on)
			e["model"].position.y = 0.55 + lift * 0.5 + sin(Time.get_ticks_msec() * 0.002 + p.x) * 0.03
		if e.has("vel"):
			e["vel"].text = str(u["v"])
		if e.has("ff"):
			e["ff"].visible = (f & 2) != 0


func _make_unit(id: String, r: Dictionary, hidden: bool, ffon: bool, prepared: bool) -> Dictionary:
	var node := Node3D.new()
	root3.add_child(node)
	var kind: String = r["kind"]
	var side: int = r["side"]
	var sz := 0.92 if kind == "ship" else 0.74
	if prepared:
		sz *= 0.5
	# gettone: bordo nero e faccia con la pedina originale
	var token := MeshInstance3D.new()
	token.mesh = _box(sz, 0.08, sz)
	token.material_override = _mat(Color(0.08, 0.08, 0.08), 0.0, 0.8)
	token.position.y = 0.04
	node.add_child(token)
	var face := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(sz * 0.98, sz * 0.98)
	face.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = UI.counter_tex(side, kind, r["cls"], r["label"], hidden or (kind == "ship" and ffon))
	fm.roughness = 0.7
	fm.uv1_scale = Vector3(1, -1, 1)
	fm.uv1_offset = Vector3(0, 1, 0)
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	face.material_override = fm
	face.position.y = 0.081
	node.add_child(face)
	var out := {"node": node, "model": null}
	if prepared:
		return out
	if not hidden:
		var m := _model(kind, r["cls"], side)
		m.position.y = 0.55
		m.set_meta("base", 1.0)
		node.add_child(m)
		out["model"] = m
		# asta trasparente fra gettone e modellino
		var stick := MeshInstance3D.new()
		stick.mesh = _cyl(0.012, 0.5)
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.8, 0.9, 1.0, 0.35)
		stick.material_override = sm
		stick.position.y = 0.33
		node.add_child(stick)
	else:
		var blip := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.12
		sp.height = 0.24
		blip.mesh = sp
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(UI.SIDE[side], 0.9)
		bm.emission_enabled = true
		bm.emission = UI.SIDE[side]
		blip.material_override = bm
		blip.position.y = 0.4
		node.add_child(blip)
	# segnalino di velocità
	var vel := Label3D.new()
	vel.font = UI.font_bold
	vel.font_size = 72
	vel.pixel_size = 0.005
	vel.outline_size = 14
	vel.outline_modulate = Color(0, 0, 0)
	vel.modulate = Color(1, 1, 1)
	vel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	vel.position = Vector3(0, 0.95 if kind == "ship" else 0.7, 0)
	vel.no_depth_test = true
	node.add_child(vel)
	out["vel"] = vel
	if kind == "ship":
		var ff := MeshInstance3D.new()
		var fsp := SphereMesh.new()
		fsp.radius = 0.62
		fsp.height = 1.24
		ff.mesh = fsp
		var ffm := StandardMaterial3D.new()
		ffm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ffm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ffm.albedo_color = Color(UI.CYAN, 0.16)
		ffm.cull_mode = BaseMaterial3D.CULL_DISABLED
		ff.material_override = ffm
		ff.position.y = 0.5
		ff.visible = ffon
		node.add_child(ff)
		out["ff"] = ff
	return out


# ---------------------------------------------------------------- sovrapposizioni ed effetti

func _hex_fill(im: ImmediateMesh, h: Vector2i, col: Color, y := 0.03, scl := 0.92) -> void:
	var c := Hex.center(h, 1.0)
	var pts := Hex.corners(c, scl)
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		im.surface_set_color(col)
		im.surface_add_vertex(Vector3(c.x, y, c.y))
		im.surface_add_vertex(Vector3(a.x, y, a.y))
		im.surface_add_vertex(Vector3(b.x, y, b.y))


func _seg(im: ImmediateMesh, a: Vector2, b: Vector2, col: Color, w := 0.06, y := 0.05) -> void:
	var d := (b - a)
	if d.length() < 0.001:
		return
	var n := d.orthogonal().normalized() * w * 0.5
	var p := [a + n, a - n, b - n, b + n]
	im.surface_set_color(col)
	im.surface_add_vertex(Vector3(p[0].x, y, p[0].y))
	im.surface_add_vertex(Vector3(p[1].x, y, p[1].y))
	im.surface_add_vertex(Vector3(p[2].x, y, p[2].y))
	im.surface_add_vertex(Vector3(p[0].x, y, p[0].y))
	im.surface_add_vertex(Vector3(p[2].x, y, p[2].y))
	im.surface_add_vertex(Vector3(p[3].x, y, p[3].y))


func _arrow3(im: ImmediateMesh, c: Vector2, ang: float, l: float, col: Color) -> void:
	var v := Vector2(cos(ang), sin(ang))
	var nn := Vector2(-v.y, v.x)
	_seg(im, c - v * l * 0.5, c + v * l * 0.2, col, 0.07)
	var tip := c + v * l * 0.5
	var b1 := c + v * l * 0.15 + nn * l * 0.22
	var b2 := c + v * l * 0.15 - nn * l * 0.22
	im.surface_set_color(col)
	im.surface_add_vertex(Vector3(tip.x, 0.06, tip.y))
	im.surface_add_vertex(Vector3(b1.x, 0.06, b1.y))
	im.surface_add_vertex(Vector3(b2.x, 0.06, b2.y))


func _draw_overlay() -> void:
	var im: ImmediateMesh = _ov_mesh.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	# un triangolo invisibile perché la superficie non resti vuota
	im.surface_set_color(Color(0, 0, 0, 0))
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3(0.001, 0, 0))
	im.surface_add_vertex(Vector3(0, 0, 0.001))
	for h in ov.get("hl", {}):
		_hex_fill(im, h, Color(ov["hl"][h], 0.35))
		any = true
	if hover.x > -999:
		_hex_fill(im, hover, Color(UI.YELLOW, 0.12), 0.025, 1.0)
	for pth in ov.get("paths", []):
		var col: Color = pth.get("col", UI.YELLOW)
		var prev := Hex.center(pth["from"], 1.0)
		for h in pth["hexes"]:
			var c := Hex.center(h, 1.0)
			_seg(im, prev, c, Color(col, 0.85), 0.08)
			_hex_fill(im, h, Color(col, 0.18), 0.035, 0.25)
			prev = c
		if pth.has("ghost"):
			var g: Dictionary = pth["ghost"]
			_arrow3(im, Hex.center(g["hex"], 1.0), Hex.dir_angle(g["dir"]), 0.7, col)
	for ar in ov.get("arrows", []):
		var c := Hex.center(ar[0], 1.0)
		for d in ar[1]:
			var sel: bool = ar.size() > 2 and int(ar[2]) == int(d)
			_arrow3(im, c + Hex.dir_vec(d) * 0.25, Hex.dir_angle(d), 0.5, UI.YELLOW if sel else UI.CYAN)
	var units: Dictionary = state.get("units", {})
	var sel: String = ov.get("sel", "")
	if units.has(sel):
		var p: Vector2 = units[sel]["p"]
		for i in 24:
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			_seg(im, p + Vector2(cos(a0), sin(a0)) * 0.62, p + Vector2(cos(a1), sin(a1)) * 0.62, UI.YELLOW, 0.06, 0.1)
	for id in ov.get("targets", {}):
		if units.has(id):
			var p: Vector2 = units[id]["p"]
			for i in 24:
				var a0 := TAU * i / 24.0
				var a1 := TAU * (i + 1) / 24.0
				_seg(im, p + Vector2(cos(a0), sin(a0)) * 0.6, p + Vector2(cos(a1), sin(a1)) * 0.6, UI.RED, 0.07, 0.1)
	im.surface_end()
	_labels()


var _label_nodes: Array = []

func _labels() -> void:
	for n in _label_nodes:
		n.queue_free()
	_label_nodes = []
	var units: Dictionary = state.get("units", {})
	var items := []
	for id in ov.get("targets", {}):
		if units.has(id):
			var p: Vector2 = units[id]["p"]
			items.append([Vector3(p.x, 1.45, p.y), ov["targets"][id]])
	for h in ov.get("labels", {}):
		var c := Hex.center(h, 1.0)
		items.append([Vector3(c.x, 0.4, c.y + 0.5), ov["labels"][h]])
	for it in items:
		var lb := Label3D.new()
		lb.text = it[1]
		lb.font = UI.font_bold
		lb.font_size = 56
		lb.pixel_size = 0.006
		lb.modulate = UI.YELLOW
		lb.outline_size = 12
		lb.outline_modulate = Color(0, 0, 0)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.position = it[0]
		root3.add_child(lb)
		_label_nodes.append(lb)


var _fx_nodes: Array = []

func _draw_fx() -> void:
	for n in _fx_nodes:
		n.queue_free()
	_fx_nodes = []
	for f in state.get("fx", []):
		var t: float = f.get("t", 0.0)
		if t < 0.0 or t > 1.0:
			continue
		match f["k"]:
			"beam":
				_shot3(f["a"], f["b"], str(f["w"]), bool(f["hit"]), t)
			"boom":
				_boom3(f["p"], t)
			"spark":
				var c: Vector2 = f["p"]
				_flash(Vector3(c.x, 0.55, c.y), 0.2 + t * 0.5, UI.CYAN, (1.0 - t) * 0.6)
			"text":
				_text3(f["p"], str(f["txt"]), bool(f["bad"]), t)
			"warp":
				var c: Vector2 = f["p"]
				_flash(Vector3(c.x, 0.55, c.y), 0.3 + t * 2.0, Color(0.7, 0.85, 1.0), (1.0 - t) * 0.7)
			"puff":
				var c: Vector2 = f["p"]
				_flash(Vector3(c.x, 0.5, c.y), 0.3 + t * 0.4, Color(1, 1, 1), (1.0 - t) * 0.4)


var _mats := {}

func _glow(col: Color, al := 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [col.to_html(), snappedf(al, 0.05)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col, al)
	if al < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.5
	_mats[key] = m
	return m


func _fxmesh(mesh: Mesh, mat: Material, pos: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.basis = basis
	mi.position = pos
	root3.add_child(mi)
	_fx_nodes.append(mi)
	return mi


func _light(p: Vector3, col: Color, e: float, r := 3.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = e
	l.omni_range = r
	l.position = p
	root3.add_child(l)
	_fx_nodes.append(l)


## colpi diversi per tipo di fuoco (stessi tempi dell'effetto 2D)
func _shot3(a2: Vector2, b2: Vector2, w: String, hit: bool, t: float) -> void:
	var a := Vector3(a2.x, 0.6, a2.y)
	var b := Vector3(b2.x, 0.6, b2.y)
	var dir := (b - a)
	if dir.length() < 0.01:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var nrm := Vector3(-dir.z, 0, dir.x)
	var end := b if hit else b + nrm * 0.8 + dir * 1.6
	var pt: Array = FX2D.pattern(w)
	var particle := w.begins_with("p")
	var col := FX2D.PLASMA if particle else FX2D.LASER
	var arrive := 0.0
	var q := Basis(Quaternion(Vector3.UP, dir))
	if t < 0.14 + float(pt[1]) * int(pt[0]):
		_flash(a + dir * 0.45, 0.16, col, 0.9)
	for i in int(pt[0]):
		var t0: float = i * pt[1]
		var k: float = (t - t0) / pt[2]
		arrive = maxf(arrive, t0 + pt[2])
		if k < 0.0 or k > 1.0:
			continue
		var lat := 0.0
		if w == "lbb":
			lat = (float(i) - 2.0) * 0.06
		elif w == "pbb":
			lat = (float(i) - 1.0) * 0.9 * 4.0 * k * (1.0 - k)
		var head := a.lerp(end, k) + nrm * lat
		if particle:
			var r := 0.22 if w == "pbb" else 0.18
			var sp := SphereMesh.new()
			sp.radius = r
			sp.height = r * 2
			_fxmesh(sp, _glow(Color(1, 1, 1)), head)
			var halo := SphereMesh.new()
			halo.radius = r * 1.9
			halo.height = r * 3.8
			_fxmesh(halo, _glow(FX2D.PLASMA, 0.35), head)
			for j in 4:
				var tr := SphereMesh.new()
				tr.radius = r * (0.8 - j * 0.15)
				tr.height = tr.radius * 2
				_fxmesh(tr, _glow(FX2D.PLASMA2, 0.3 - j * 0.06), head - dir * 0.14 * (j + 1))
			_light(head, FX2D.PLASMA, 2.5, 2.5)
		else:
			var L := 0.9 if w == "lb" else 0.6
			var c2: Color = FX2D.LASER if (w == "lb" or i % 2 == 0) else FX2D.LASER2
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.035
			bolt.bottom_radius = 0.035
			bolt.height = L
			bolt.radial_segments = 8
			_fxmesh(bolt, _glow(Color(1, 0.95, 0.85)), head - dir * L * 0.5, q)
			var gl := CylinderMesh.new()
			gl.top_radius = 0.09
			gl.bottom_radius = 0.09
			gl.height = L * 1.1
			gl.radial_segments = 8
			_fxmesh(gl, _glow(c2, 0.4), head - dir * L * 0.5, q)
			_light(head, c2, 2.0, 2.0)
	if w == "pbb" and t < arrive:
		# fulmini fra la nave e i globi
		var r := RandomNumberGenerator.new()
		r.seed = int(t * 40.0)
		var tip := a.lerp(end, clampf(t / arrive, 0.0, 1.0))
		var prev := a
		for j in 7:
			var p2 := a.lerp(tip, float(j + 1) / 7.0) + nrm * r.randf_range(-0.25, 0.25) + Vector3(0, r.randf_range(-0.15, 0.15), 0)
			var seg := p2 - prev
			if seg.length() > 0.01:
				var cy := CylinderMesh.new()
				cy.top_radius = 0.02
				cy.bottom_radius = 0.02
				cy.height = seg.length()
				cy.radial_segments = 4
				_fxmesh(cy, _glow(FX2D.PLASMA2, 0.85), (prev + p2) * 0.5, Basis(Quaternion(Vector3.UP, seg.normalized())))
			prev = p2
	if not hit and t > arrive:
		_text3(b2, "mancato", false, clampf((t - arrive) / maxf(0.01, 1.0 - arrive), 0.0, 1.0), Color(0.75, 0.8, 0.9))
	if hit and t >= arrive * 0.95:
		var k := clampf((t - arrive) / maxf(0.01, 1.0 - arrive), 0.0, 1.0)
		var big := w.ends_with("bb")
		_flash(b, (0.25 + 0.5 * k) * (1.3 if big else 1.0), Color(1, 0.95, 0.8), 1.0 - k)
		_flash(b, (0.4 + 0.8 * k) * (1.3 if big else 1.0), col, (1.0 - k) * 0.5)
		var r := RandomNumberGenerator.new()
		r.seed = int(b.x * 13 + b.z * 7)
		for i in (14 if big else 9):
			var ang := atan2(dir.z, dir.x) + r.randf_range(-1.6, 1.6)
			var v := Vector3(cos(ang), r.randf_range(-0.3, 0.8), sin(ang)).normalized()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.05, 0.05, 0.05)
			_fxmesh(bx, _glow(Color("#ffe39a") if not particle else Color.WHITE, 1.0 - k), b + v * r.randf_range(0.6, 1.4) * 1.2 * k)


func _boom3(c2: Vector2, t: float) -> void:
	var c := Vector3(c2.x, 0.55, c2.y)
	var r := RandomNumberGenerator.new()
	r.seed = int(c2.x * 13 + c2.y * 7)
	if t < 0.22:
		_flash(c, 0.5 + 3.0 * t, Color(1, 1, 1), 1.0 - t / 0.22)
	var fc: Color
	if t < 0.3:
		fc = Color("#fff3a0").lerp(Color("#ffb030"), t / 0.3)
	elif t < 0.6:
		fc = Color("#ffb030").lerp(Color("#e0402a"), (t - 0.3) / 0.3)
	else:
		fc = Color("#e0402a").lerp(Color("#3a2a28"), (t - 0.6) / 0.4)
	for i in 7:
		var off := Vector3(r.randf_range(-1, 1), r.randf_range(-0.6, 1), r.randf_range(-1, 1)) * 0.45 * sqrt(t)
		var rad := (0.22 + 0.6 * sqrt(t)) * r.randf_range(0.6, 1.1)
		var sp := SphereMesh.new()
		sp.radius = rad
		sp.height = rad * 2
		sp.radial_segments = 12
		sp.rings = 6
		_fxmesh(sp, _glow(fc, clampf(0.8 * pow(1.0 - t, 1.2), 0.0, 1.0)), c + off)
	# onda d'urto
	var ring := TorusMesh.new()
	ring.inner_radius = 0.3 + 2.4 * t
	ring.outer_radius = ring.inner_radius + 0.08 * (1.0 - t) + 0.02
	ring.rings = 32
	_fxmesh(ring, _glow(Color(1.0, 0.85, 0.6), clampf(0.8 * (1.0 - t), 0.0, 1.0)), c)
	# detriti
	for i in 18:
		var v := Vector3(r.randf_range(-1, 1), r.randf_range(-0.4, 1), r.randf_range(-1, 1)).normalized()
		var sp := r.randf_range(0.8, 2.4)
		var bx := BoxMesh.new()
		bx.size = Vector3(0.07, 0.05, 0.12)
		_fxmesh(bx, _glow(Color("#ffd27a").lerp(Color("#c0402a"), t), clampf(1.0 - t, 0.0, 1.0)), c + v * sp * (1.0 - pow(1.0 - t, 2.0)), Basis.from_euler(Vector3(t * 9 + i, t * 7, i)))
	_light(c, Color(1.0, 0.6, 0.25), 6.0 * (1.0 - t), 5.0)


func _text3(p: Vector2, txt: String, bad: bool, t: float, col := Color(0, 0, 0, 0)) -> void:
	if txt == "":
		return
	if col.a == 0.0:
		col = UI.RED if bad else UI.YELLOW
	var al := clampf(minf(t / 0.12, (1.0 - t) / 0.3), 0.0, 1.0)
	var lb := Label3D.new()
	lb.text = txt
	lb.font = UI.font_bold
	lb.font_size = 72 if bad else 60
	lb.pixel_size = 0.006
	lb.modulate = Color(col, al)
	lb.outline_size = 14
	lb.outline_modulate = Color(0, 0, 0, al * 0.9)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.position = Vector3(p.x, 1.3 + 0.8 * t, p.y)
	root3.add_child(lb)
	_fx_nodes.append(lb)


func _flash(p: Vector3, r: float, col: Color, al: float) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2
	sp.radial_segments = 16
	sp.rings = 8
	mi.mesh = sp
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, clampf(al, 0.0, 1.0) * 0.7)
	mi.material_override = m
	mi.position = p
	root3.add_child(mi)
	_fx_nodes.append(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0 * al
	l.omni_range = 3.0
	l.position = p
	root3.add_child(l)
	_fx_nodes.append(l)
