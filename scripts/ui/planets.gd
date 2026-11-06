class_name Planets
extends RefCounted
## Pianeti e lune per la mappa 2D e il tabellone 3D: il pianeta (raggio 1,75 esagoni, copre metà degli
## esagoni vicini) gira su se stesso con le nuvole un po' più veloci, l'atmosfera brilla sul bordo e una o
## due lune gli girano attorno. Le texture si rifanno con tools/genera_pianeti.py.

const R := 1.75                  # raggio del pianeta in lati di esagono

## aspetto di ogni pianeta degli scenari (gli altri usano "terra")
const LOOKS := {
	"Esata": {"surf": "terra", "atmo": Color(0.45, 0.7, 1.0), "spin": 0.012,
		"moons": [{"tex": "luna_grigia", "r": 0.36, "orbit": 2.75, "speed": 0.22, "phase": 0.6, "incl": 0.38}]},
	"Zaraznov": {"surf": "deserto", "atmo": Color(1.0, 0.65, 0.4), "spin": 0.009,
		"moons": [{"tex": "luna_grigia", "r": 0.3, "orbit": 2.6, "speed": 0.3, "phase": 2.0, "incl": 0.32},
			{"tex": "luna_ocra", "r": 0.22, "orbit": 3.35, "speed": -0.17, "phase": 4.2, "incl": 0.5}]},
	"Kerberos": {"surf": "gassoso", "atmo": Color(0.85, 0.7, 1.0), "spin": 0.02,
		"moons": [{"tex": "luna_ocra", "r": 0.34, "orbit": 2.8, "speed": 0.25, "phase": 1.0, "incl": 0.3},
			{"tex": "luna_grigia", "r": 0.24, "orbit": 3.45, "speed": 0.14, "phase": 3.4, "incl": 0.45}]},
}


static func look(name: String) -> Dictionary:
	return LOOKS.get(name, LOOKS["Esata"])


static func tex(n: String) -> Texture2D:
	return UI.tex("res://assets/planets/%s.webp" % n)


# ================================================================ 2D

const SHADER_2D := """
shader_type canvas_item;
uniform sampler2D surf : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds : source_color, filter_linear_mipmap, repeat_enable;
uniform float has_clouds = 1.0;
uniform float spin = 0.012;
uniform float cspin = 0.02;
uniform vec4 atmo : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform float atmo_on = 1.0;
// lune: il quadrato copre l'orbita; la luna si disegna solo nella metà giusta (dietro o davanti al pianeta)
uniform float moon = 0.0;
uniform float m_r = 0.1;
uniform float m_speed = 0.2;
uniform float m_phase = 0.0;
uniform float m_incl = 0.4;
uniform float front = 1.0;

vec4 sphere(vec2 q, float sp) {
	float d2 = dot(q, q);
	vec3 n = vec3(q.x, -q.y, sqrt(max(0.0, 1.0 - d2)));
	// asse inclinato di poco
	float ti = 0.35;
	vec3 m = vec3(n.x, n.y * cos(ti) - n.z * sin(ti), n.y * sin(ti) + n.z * cos(ti));
	float lon = atan(m.z, m.x);
	float lat = asin(clamp(m.y, -1.0, 1.0));
	vec2 uv = vec2(lon / (2.0 * PI) + TIME * sp, 0.5 - lat / PI);
	vec3 col = texture(surf, uv).rgb;
	if (has_clouds > 0.5) {
		vec4 cl = texture(clouds, vec2(lon / (2.0 * PI) + TIME * cspin, uv.y));
		col = mix(col, cl.rgb, cl.a);
	}
	vec3 L = normalize(vec3(-0.55, 0.45, 0.7));
	float lit = clamp(dot(n, L), 0.0, 1.0);
	col *= 0.14 + 1.0 * lit;
	col += atmo.rgb * pow(1.0 - n.z, 3.0) * 0.55 * atmo_on * (0.3 + lit);
	return vec4(col, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (moon < 0.5) {
		float Rs = 0.86;
		vec2 q = p / Rs;
		float d2 = dot(q, q);
		if (d2 > 1.0) {
			float h = (sqrt(d2) - 1.0) / (1.0 / Rs - 1.0);
			COLOR = vec4(atmo.rgb, atmo_on * 0.55 * pow(clamp(1.0 - h, 0.0, 1.0), 2.5));
		} else {
			COLOR = sphere(q, spin);
		}
	} else {
		float a = TIME * m_speed + m_phase;
		vec2 c = vec2(cos(a), sin(a) * m_incl) * (1.0 - m_r);
		bool behind = sin(a) < 0.0;
		if ((front > 0.5) == behind) {
			discard;
		}
		vec2 q = (p - c) / m_r;
		if (dot(q, q) > 1.0) {
			discard;
		}
		COLOR = sphere(q, spin * 0.5);
	}
}
"""

static var _sh2: Shader


static func _mat2(name: String) -> ShaderMaterial:
	if _sh2 == null:
		_sh2 = Shader.new()
		_sh2.code = SHADER_2D
	var lk := look(name)
	var m := ShaderMaterial.new()
	m.shader = _sh2
	m.set_shader_parameter("surf", tex(lk["surf"]))
	m.set_shader_parameter("clouds", tex(lk["surf"] + "_nuvole"))
	m.set_shader_parameter("spin", lk["spin"])
	m.set_shader_parameter("cspin", lk["spin"] * 1.7)
	m.set_shader_parameter("atmo", lk["atmo"])
	return m


## nodo 2D del pianeta con le lune, centrato in c (unità: S pixel per lato di esagono)
static func node_2d(c: Vector2, S: float, name: String) -> Node2D:
	var n := Node2D.new()
	n.position = c
	var lk := look(name)
	var moons: Array = lk["moons"]
	# lune dietro, pianeta, lune davanti
	for front in [0.0, 1.0]:
		if front > 0.5:
			var pr := ColorRect.new()
			var side := R * S * 2.0 / 0.86
			pr.size = Vector2(side, side)
			pr.position = -pr.size * 0.5
			pr.material = _mat2(name)
			pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			n.add_child(pr)
		for mo in moons:
			var mr := ColorRect.new()
			var o: float = float(mo["orbit"]) * S
			mr.size = Vector2(o * 2.0, o * 2.0)
			mr.position = -mr.size * 0.5
			var mm := _mat2(name)
			mm.set_shader_parameter("surf", tex(mo["tex"]))
			mm.set_shader_parameter("has_clouds", 0.0)
			mm.set_shader_parameter("atmo_on", 0.0)
			mm.set_shader_parameter("moon", 1.0)
			mm.set_shader_parameter("m_r", float(mo["r"]) / float(mo["orbit"]))
			mm.set_shader_parameter("m_speed", mo["speed"])
			mm.set_shader_parameter("m_phase", mo["phase"])
			mm.set_shader_parameter("m_incl", mo["incl"])
			mm.set_shader_parameter("front", front)
			mr.material = mm
			mr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			n.add_child(mr)
	return n


# ================================================================ 3D

const ATMO_3D := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.45, 0.7, 1.0, 1.0);
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col.rgb * pow(f, 2.5) * 1.4;
}
"""

static var _sh3: Shader


## pianeta 3D con nuvole, atmosfera e lune; ritorna il nodo (da far girare con spin_3d)
static func node_3d(name: String) -> Node3D:
	var lk := look(name)
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	body.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex(lk["surf"])
	mat.roughness = 0.85
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	body.material_override = mat
	body.rotation.z = 0.35
	root.add_child(body)
	var cl := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = R * 1.015
	cm.height = R * 2.03
	cm.radial_segments = 64
	cm.rings = 32
	cl.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_texture = tex(lk["surf"] + "_nuvole")
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.roughness = 1.0
	cl.material_override = cmat
	cl.rotation.z = 0.35
	root.add_child(cl)
	if _sh3 == null:
		_sh3 = Shader.new()
		_sh3.code = ATMO_3D
	var at := MeshInstance3D.new()
	var amesh := SphereMesh.new()
	amesh.radius = R * 1.09
	amesh.height = R * 2.18
	amesh.radial_segments = 48
	amesh.rings = 24
	at.mesh = amesh
	var am := ShaderMaterial.new()
	am.shader = _sh3
	am.set_shader_parameter("col", lk["atmo"])
	at.material_override = am
	root.add_child(at)
	var moons := []
	for mo in lk["moons"]:
		var piv := Node3D.new()
		piv.rotation.x = float(mo["incl"]) * 0.6
		root.add_child(piv)
		var mm := MeshInstance3D.new()
		var ms := SphereMesh.new()
		ms.radius = float(mo["r"])
		ms.height = float(mo["r"]) * 2.0
		mm.mesh = ms
		var mmat := StandardMaterial3D.new()
		mmat.albedo_texture = tex(mo["tex"])
		mmat.roughness = 1.0
		mm.material_override = mmat
		mm.position = Vector3(float(mo["orbit"]), 0, 0)
		piv.add_child(mm)
		moons.append({"pivot": piv, "speed": float(mo["speed"]), "phase": float(mo["phase"]), "moon": mm})
	root.set_meta("body", body)
	root.set_meta("clouds", cl)
	root.set_meta("moons", moons)
	root.set_meta("spin", float(lk["spin"]))
	return root


static func spin_3d(root: Node3D, t: float) -> void:
	var sp: float = root.get_meta("spin")
	(root.get_meta("body") as Node3D).rotation.y = t * sp * TAU
	(root.get_meta("clouds") as Node3D).rotation.y = t * sp * 1.7 * TAU
	for mo in root.get_meta("moons"):
		(mo["pivot"] as Node3D).rotation.y = -(t * float(mo["speed"]) + float(mo["phase"]))
		(mo["moon"] as Node3D).rotation.y = t * 0.3
