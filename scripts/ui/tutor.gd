class_name Tutor
extends Control
## Tutorial guidato sul primo scenario (Il duello): spiega le fasi quando capitano per la prima volta
## e mette in evidenza i pulsanti da usare. Reagisce agli eventi della partita, senza bloccarla.

var g                            # vista di gioco
var panel: PanelContainer
var title_lbl: Label
var body: RichTextLabel
var count_lbl: Label
var next_btn: Button
var hide_btn: Button
var show_btn: Button
var queue: Array = []            # passi in attesa
var step := {}                   # passo mostrato
var seen := {}                   # capitoli già mostrati
var done_steps := 0
var _t := 0.0
var _targets: Array = []         # rettangoli globali da evidenziare

const W := 600.0

## capitoli: evento -> passi {t: titolo, x: testo, hl: [testi dei pulsanti], until: "next" | "submit"}
const CH := {
	"start": [
		{"t": "Benvenuto in DeltaVee",
		"x": "Comandi il [color=#ff6a13]Piccolo E[/color] dei tagliagole (arancione). Ti insegue il [color=#7ed321]Piccolo D[/color] della guardia locale (verde), guidato da un'IA facile. [b]Vince chi distrugge per primo l'astronave nemica.[/b]\n\nSulla mappa: trascina per spostarti, rotella o due dita per lo zoom, [b]Centra[/b] rifà l'inquadratura. Tocca una pedina per vederne la scheda a destra."},
		{"t": "Leggere le pedine",
		"x": "Ogni pedina punta nella sua direzione, come le lancette di un orologio: le 12 direzioni si chiamano «ore». Il quadratino grigio è la velocità: quanti esagoni farà la nave nel prossimo movimento.\n\nVerso le ore pari la nave attraversa un lato dell'esagono; verso le ore dispari punta a un vertice e procede a zig-zag."},
		{"t": "Lo spazio è newtoniano",
		"x": "Le navi [b]non si fermano[/b]: nel movimento ognuna va avanti da sola, dritta e alla stessa velocità, finché non le dai un ordine nella fase di comando.\n\nOgni turno ha due metà: prima un lato si muove, poi l'altro dà i comandi e infine il primo spara; poi le parti si invertono. Quindi decidi le manovre dopo aver visto muovere il nemico, e spari subito dopo esserti mosso."},
	],
	"dec_fire": [
		{"t": "Fase di fuoco",
		"x": "Ora puoi sparare. A destra trovi le armi della nave: il [b]burster[/b] (raffica laser) e il modulo [b]Cacciatore[/b] (laser, particelle e missili). Scegli un'arma e poi tocca il nemico sulla mappa: compare la probabilità di colpire.\n\nPiù il bersaglio è lontano e più è alta la velocità relativa, più il colpo è difficile: da lontano spesso è impossibile.",
		"hl": ["Raffica laser"]},
		{"t": "Passare il turno",
		"x": "Se non puoi o non vuoi sparare, premi [b]Fine fuoco[/b]. [b]Suggerisci (IA)[/b] propone il colpo che farebbe il computer: puoi accettarlo o cambiarlo.",
		"hl": ["Fine fuoco", "Suggerisci (IA)"], "until": "submit"},
	],
	"dec_cmd": [
		{"t": "Fase di comando",
		"x": "Qui decidi la manovra per il prossimo movimento. La [color=#f4e46a]linea gialla[/color] sulla mappa mostra dove andrà la nave con gli ordini attuali.\n\nOgni manovra consuma energia: i blocchi rimasti sono nella barra arancione sotto il nome della nave. Le schede Caratteristiche e Moduli mostrano il resto della nave."},
		{"t": "Velocità",
		"x": "Con [b]meno[/b] e [b]più[/b] cambi la velocità. C'è un limite per turno e ogni cambio costa energia.",
		"hl": ["−", "+"]},
		{"t": "Direzione",
		"x": "Con [b]Sx[/b] e [b]Dx[/b] la nave vira di un'ora a sinistra o a destra. Se ha energia può virare di più ore nello stesso turno.",
		"hl": ["Sx", "Dx"]},
		{"t": "Un consiglio tattico",
		"x": "Per colpire servono distanza corta e velocità relativa bassa: prova ad affiancarti al nemico, nella sua stessa direzione e alla sua velocità.\n\nAttento però ai suoi missili: puntano sugli esagoni dove arriverai."},
		{"t": "Dare gli ordini",
		"x": "Quando sei pronto premi [b]Fine comandi[/b]. In caso di dubbio, [b]Suggerisci (IA)[/b] imposta la manovra che sceglierebbe il computer.",
		"hl": ["Fine comandi", "Suggerisci (IA)"], "until": "submit"},
	],
	"launch": [
		{"t": "Missili!",
		"x": "È partito un missile. I missili si muovono come le navi; quando entrano nell'esagono di un bersaglio tentano l'[b]intercettazione[/b], con un dado che dipende dalla velocità relativa.\n\nIl missile non guidato accelera da solo di 1 ogni turno; quello intelligente insegue il bersaglio. Puoi provare ad abbatterli sparando, oppure cambiare rotta."},
	],
	"aim": [
		{"t": "Lanciare un missile",
		"x": "Tocca uno degli esagoni azzurri davanti alla nave, poi scegli direzione e velocità e premi [b]LANCIA![/b]. Conviene lanciare dove il nemico arriverà al prossimo movimento.",
		"hl": ["LANCIA!"]},
	],
	"target": [
		{"t": "Prendere la mira",
		"x": "Sotto l'arma vedi gittata, velocità relativa e il numero che serve sul dado a dieci facce. Se il colpo è possibile premi [b]FUOCO![/b]: il risultato arriva subito.",
		"hl": ["FUOCO!"]},
	],
	"hit_me": [
		{"t": "Sei stato colpito",
		"x": "Sulla mappa compare la parte colpita della tua nave. Tocca la tua pedina per vederne la scheda: ogni parte passa da intatta a vulnerabile, danneggiata e distrutta.\n\nSe ponte e motore sono distrutti e con loro più di metà dei moduli, la nave è perduta."},
	],
	"dec_hitpart": [
		{"t": "Scegli dove colpire",
		"x": "Il tuo colpo è andato a segno. Il dado indica quali parti possono essere colpite e scegli tu quale: ponte e motore sono le più importanti, i moduli contengono armi, missili ed energia."},
	],
	"end": [
		{"t": "Fine del tutorial",
		"x": "Ora conosci le basi. Puoi rivedere tutta la partita con il replay. Poi dal menu prova gli altri scenari: le [b]Regole[/b] spiegano il resto, cioè pianeti, caccia, campi di forza, raggi traenti e salto nell'iperspazio."},
	],
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	var st := UI.panel_style(Color(0.03, 0.05, 0.12, 0.96), UI.YELLOW, 2, 8)
	st.set_content_margin_all(14)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 12
	panel.add_theme_stylebox_override("panel", st)
	panel.position = Vector2(16, g.TOP_H + 44)
	panel.custom_minimum_size = Vector2(W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var hr := HBoxContainer.new()
	vb.add_child(hr)
	title_lbl = UI.title("", 30)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(title_lbl)
	count_lbl = UI.label("Tutorial", 16, UI.MUTED, UI.font_semi)
	hr.add_child(count_lbl)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(W - 28, 0)
	body.add_theme_font_size_override("normal_font_size", 19)
	body.add_theme_font_size_override("bold_font_size", 19)
	body.add_theme_font_override("bold_font", UI.font_bold)
	body.add_theme_color_override("default_color", UI.TEXT)
	vb.add_child(body)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 10)
	br.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(br)
	hide_btn = UI.button("Nascondi", 140, 42, 18)
	hide_btn.pressed.connect(func(): _collapse(true))
	br.add_child(hide_btn)
	next_btn = UI.primary(UI.button("Avanti", 160, 42, 20))
	next_btn.pressed.connect(_next)
	br.add_child(next_btn)
	show_btn = UI.primary(UI.button("Tutorial", 150, 42, 18))
	show_btn.position = Vector2(16, g.TOP_H + 44)
	show_btn.pressed.connect(func(): _collapse(false))
	show_btn.visible = false
	add_child(show_btn)
	panel.visible = false


## un evento della partita: mostra il capitolo collegato, se non è già stato visto
func event(name: String) -> void:
	if seen.has(name) or not CH.has(name):
		return
	seen[name] = true
	for s in CH[name]:
		queue.append(s)
	if step.is_empty():
		_next()


func _next() -> void:
	if queue.is_empty():
		step = {}
		panel.visible = false
		show_btn.visible = false
		_targets = []
		queue_redraw()
		return
	step = queue.pop_front()
	done_steps += 1
	title_lbl.text = step["t"]
	body.text = step["x"]
	var last := queue.is_empty()
	next_btn.visible = step.get("until", "next") == "next"
	next_btn.text = "Ho capito" if last else "Avanti"
	count_lbl.text = "Tutorial · %d" % done_steps
	_collapse(false)
	panel.reset_size()


func _collapse(c: bool) -> void:
	if step.is_empty():
		return
	panel.visible = not c
	show_btn.visible = c


func _process(dt: float) -> void:
	_t += dt
	if str(g.pending.get("type", "")) == "fire":
		if g.mode == "launch":
			event("aim")
		elif str(g.aux.get("t", "")) != "" and g.aux.has("w"):
			event("target")
	if not step.is_empty() and step.get("until", "next") == "submit" and g.pending.is_empty():
		_next()
	_targets = []
	if not step.is_empty() and panel.visible:
		for txt in step.get("hl", []):
			_find(g, txt)
	queue_redraw()


func _find(n: Node, txt: String) -> void:
	if n == self:
		return
	if n is Button and n.is_visible_in_tree() and not n.disabled and (n.text == txt or (txt.length() > 3 and n.text.begins_with(txt))):
		_targets.append(n.get_global_rect())
	for c in n.get_children():
		_find(c, txt)


func _draw() -> void:
	var inv := get_global_transform().affine_inverse()
	var a := 0.55 + 0.45 * sin(_t * 5.0)
	var grow := 4.0 + 3.0 * sin(_t * 5.0)
	for r in _targets:
		var rr: Rect2 = Rect2(inv * r.position, r.size).grow(grow)
		draw_rect(rr, Color(UI.YELLOW, 0.12 * a), true)
		draw_rect(rr, Color(UI.YELLOW, a), false, 3.0)
		# freccia disegnata (niente glifi): triangolo sopra il pulsante, che punta in basso
		var tip := Vector2(rr.get_center().x, rr.position.y - 2)
		var pts := PackedVector2Array([tip, tip + Vector2(-10, -14), tip + Vector2(10, -14)])
		draw_colored_polygon(pts, Color(UI.YELLOW, a))
