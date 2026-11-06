extends Control
## Radice dell'applicazione: alterna menu, partita e regole.

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
var _players: Array = []
var _streams := {}


func _audio_init() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		audio_on = bool(c.get_value("audio", "on", true))
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


func show_rules() -> void:
	_clear()
	var t := preload("res://scripts/ui/rules_view.gd").new()
	t.main = self
	add_child(t)
	current = t
