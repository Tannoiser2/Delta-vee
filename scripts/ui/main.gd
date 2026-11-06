extends Control
## Radice dell'applicazione: alterna menu, partita, regole e cantiere navale.

const D = preload("res://scripts/data/dv_data.gd")

var current: Control
## Collegamento a Firebase per il gioco online (resta vivo fra menu e partita).
var net: Net
## Stanza online in preparazione: {role, code, seat}. Vuota se non si è in una stanza.
var lobby := {}
## Ultime scelte del menu (si ritrovano tornando al menu).
var menu_state := {}


# ---------------------------------------------------------------- effetti sonori

const CFG := "user://deltavee.cfg"
var audio_on := true
var grid_alpha := 1.0            # opacità della griglia di esagoni (0 = solo i puntini al centro)
var _players: Array = []
var _streams := {}


func _audio_init() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		audio_on = bool(c.get_value("audio", "on", true))
		grid_alpha = clampf(float(c.get_value("vista", "griglia", 1.0)), 0.0, 1.0)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func set_audio(on: bool) -> void:
	audio_on = on
	var c := ConfigFile.new()
	c.load(CFG)
	c.set_value("audio", "on", on)
	c.save(CFG)


func set_grid_alpha(a: float) -> void:
	grid_alpha = clampf(a, 0.0, 1.0)
	var c := ConfigFile.new()
	c.load(CFG)
	c.set_value("vista", "griglia", grid_alpha)
	c.save(CFG)


## suona un effetto di assets/audio (nome senza estensione); delay in secondi
func sfx(name: String, vol_db := 0.0, delay := 0.0, pitch := 1.0) -> void:
	if not audio_on or DisplayServer.get_name() == "headless":
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): sfx(name, vol_db, 0.0, pitch))
		return
	if not _streams.has(name):
		_streams[name] = load("res://assets/audio/%s.wav" % name)
	if _streams[name] == null:
		return
	var best: AudioStreamPlayer = _players[0]
	for p in _players:
		if not p.playing:
			best = p
			break
	best.stream = _streams[name]
	best.volume_db = vol_db
	best.pitch_scale = pitch
	best.play()


func get_net() -> Net:
	if net == null:
		net = Net.new()
		add_child(net)
	return net


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.Starfield.new())
	_audio_init()
	show_menu()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _clear() -> void:
	if current != null:
		current.queue_free()
		current = null


func show_menu() -> void:
	_clear()
	var m := preload("res://scripts/ui/menu.gd").new()
	m.main = self
	add_child(m)
	current = m


func start_game(config: Dictionary) -> void:
	_clear()
	var g := preload("res://scripts/ui/game_view.gd").new()
	g.main = self
	g.config = config
	add_child(g)
	current = g


# ---------------------------------------------------------------- partita salvata

const SAVE := "user://partita.json"
const SAVE_KEYS := ["scenario", "seats", "max_turns", "ai_delay", "anim", "view3d", "seed", "custom"]


## la partita salvata ({} se non c'è)
func saved_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE):
		return {}
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or not d.has("cfg") or not d.has("dec"):
		return {}
	return d


func save_game(cfg: Dictionary, eng: DVEngine) -> void:
	var c := {}
	for k in SAVE_KEYS:
		if cfg.has(k):
			c[k] = cfg[k]
	var d := {"v": 1, "cfg": c, "dec": eng.dec_log, "turn": eng.turn, "scn": eng.scn,
		"when": Time.get_datetime_string_from_system(false, true)}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


func delete_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)


func resume_game() -> void:
	var d := saved_game()
	if d.is_empty():
		show_menu()
		return
	var cfg: Dictionary = d["cfg"].duplicate(true)
	cfg["scenario"] = int(cfg.get("scenario", 0))
	cfg["seed"] = int(cfg.get("seed", 1))
	cfg["max_turns"] = int(cfg.get("max_turns", 40))
	for st in cfg.get("seats", []):
		st["level"] = int(st.get("level", 1))
	cfg["dec"] = d["dec"]
	start_game(cfg)


# ---------------------------------------------------------------- cantiere navale

const YARD := "user://cantiere.json"
var _yard := {}


## flotte della battaglia libera (si salvano a ogni modifica)
func yard() -> Dictionary:
	if _yard.is_empty():
		_yard = D.yard_default()
		if FileAccess.file_exists(YARD):
			var f := FileAccess.open(YARD, FileAccess.READ)
			var d = JSON.parse_string(f.get_as_text()) if f != null else null
			if d is Dictionary and d.has("fleets") and d["fleets"] is Array and d["fleets"].size() == 2:
				_yard = d
	return _yard


func save_yard() -> void:
	var f := FileAccess.open(YARD, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_yard))
		f.close()


func show_shipyard() -> void:
	_clear()
	var t := preload("res://scripts/ui/shipyard.gd").new()
	t.main = self
	add_child(t)
	current = t


func show_rules() -> void:
	_clear()
	var t := preload("res://scripts/ui/rules_view.gd").new()
	t.main = self
	add_child(t)
	current = t
