extends Control
## Le regole di DeltaVee riassunte in italiano, con le tabelle.

const D = preload("res://scripts/data/dv_data.gd")

var main
var popup := false

const TEXT := """[font_size=34][color=#f4e46a]DeltaVee in breve[/color][/font_size]
Combattimento tattico fra astronavi del XXIV secolo, nel mondo del gioco di ruolo [b]Universe[/b] (SPI, 1981). Ogni esagono misura 20.000 km, ogni turno dura 15 minuti. Il movimento segue, in modo astratto, le leggi di Newton: una nave continua ad andare dritta alla sua velocità finché non le si ordina di cambiare.

[font_size=26][color=#ef6f9c]Sequenza di gioco[/color][/font_size]
Ogni turno ha sei fasi: [b]1.[/b] movimento del Giocatore 1 · [b]2.[/b] comando del Giocatore 2 (prima il rilevamento) · [b]3.[/b] fuoco del Giocatore 1 · [b]4.[/b] movimento del Giocatore 2 · [b]5.[/b] comando del Giocatore 1 · [b]6.[/b] fuoco del Giocatore 2.
Così fra il vostro comando e il vostro fuoco il nemico non si muove: sapete dove sarà.

[font_size=26][color=#ef6f9c]Movimento[/color][/font_size]
Nella vostra fase di movimento [b]ogni[/b] vostra unità avanza di tanti esagoni quanta è la sua velocità, dritta nella direzione in cui punta. Le direzioni sono 12, come le ore: le pari (12, 2, 4, 6, 8, 10) puntano a un lato dell'esagono, le dispari a un vertice e lì il percorso va a zig-zag (prima a sinistra, poi a destra), ricordando il passo anche da un turno all'altro. Si attraversano liberamente gli esagoni occupati.
Chi esce dalle mappe ne fa aggiungere un'altra; un missile che esce è perso.

[font_size=26][color=#ef6f9c]Comandi di manovra[/color][/font_size]
Si danno nella vostra fase di comando. Una nave può ricevere [b]manovra meno velocità attuale[/b] comandi (se la velocità è pari o superiore alla manovra, solo un accelera o decelera):
• [b]Accelera / Decelera[/b]: velocità ±1, fino alla «variazione» della nave per fase.
• [b]Cambio di direzione[/b]: un'ora (30°) per comando.
• [b]Scarto laterale[/b]: la nave si sposta subito in un esagono adiacente senza cambiare rotta (uno per fase; non in pianeti o asteroidi).
• [b]Prepara salto / Salta / Annulla[/b]: solo negli scenari che lo permettono.
Energia: più di un accelera/decelera/cambio di direzione costa [b]1 blocco[/b] (un blocco = il consumo della nave in unità di energia); lo scarto costa 1 blocco in più. Con il motore danneggiato ogni comando costa un blocco. I caccia pagano in unità, i missili 1 unità per comando.
Con il campo di forza attivo o il salto preparato non si manovra.

[font_size=26][color=#ef6f9c]Comandi di battaglia[/color][/font_size]
Li danno i moduli: armi leggere, pesanti e arsenale 1 ciascuno, comunicazioni di battaglia 2.
• [b]Prepara missile[/b] (i tipi segnati con * nella scheda): il missile resta coperto sopra la nave e si lancia da una fase di fuoco successiva. Al massimo tanti missili pronti quanti i moduli che li portano.
• [b]Guida missile[/b]: un comando per ogni missile guidato che si vuole manovrare in questa fase.
• [b]Ricerca attiva[/b]: scopre le pedine nemiche coperte entro 6 esagoni (10 con le comunicazioni di battaglia).
• [b]Prepara caccia / Lancia caccia[/b] (in due fasi diverse) e [b]Rientro[/b] del caccia (stesso esagono, velocità e direzione della nave).
• [b]Raggio traente[/b]: 1 comando di manovra a un'unità entro 4 esagoni (civiltà 7) o 2 entro 6 (civiltà 8), anche nemica; costa 2 × il blocco del bersaglio per comando.
• [b]Campo di forza[/b]: attivarlo costa un blocco; protegge dai missili, non dai laser.
• [b]Aggancio[/b]: due navi nello stesso esagono con la stessa velocità e direzione.

[font_size=26][color=#ef6f9c]Fuoco[/color][/font_size]
Il burster di ogni nave spara una volta (classe 1: raffica laser; classe 2: anche sbarramento); ogni modulo d'armi spara o lancia una volta (l'arsenale due); le comunicazioni di battaglia danno un fuoco in più. Un caccia spara una volta con il suo burster.
[b]Valore del bersaglio[/b] = gittata (in esagoni, contando quello del bersaglio) + velocità relativa ridotta dal puntamento (mai sotto zero). La [b]velocità relativa[/b] è la differenza delle velocità se le direzioni sono uguali o vicine, la somma se opposte, altrimenti si legge nella tabella. Se le due unità stanno sulla stessa linea di rotta la velocità relativa si dimezza; se hanno identiche direzione e velocità è zero e la gittata si dimezza.
Poi un d10 sulla tabella dei risultati: se colpisce, un secondo d10 dice quale parte è colpita.

[font_size=26][color=#ef6f9c]Danni[/color][/font_size]
Ogni parte ha la corazza 0, 1 o 2: con corazza 0 il primo colpo la distrugge (X); con 1 il primo la danneggia (D) e il secondo la distrugge; con 2 si passa da vulnerabile (V) a danneggiata e distrutta. Ponte danneggiato: manovra −2 e niente scarti; distrutto: manovra 1. Motore danneggiato: ogni manovra costa un blocco; distrutto: nessuna manovra. Moduli d'armi danneggiati: perdono i missili e solo raffiche. Una nave è distrutta con ponte, motore e più di metà dei moduli distrutti, oppure se un missile la intercetta senza campo di forza.
Un missile colpito si distrugge solo con 2 (o 1 se scoperto) sulla tabella dei colpi.

[font_size=26][color=#ef6f9c]Missili[/color][/font_size]
Si lanciano in uno degli esagoni davanti alla nave, a velocità della nave ±1 (minimo 1). [b]Non guidati[/b]: accelerano di 1 a ogni vostra fase di comando. [b]Guidati[/b]: manovrano con il comando «Guida» della nave. [b]Intelligenti[/b]: manovrano da soli. [b]MIMS[/b]: come gli intelligenti, ma una volta possono aprirsi e lanciare quattro non guidati. Ogni manovra di un missile consuma un'unità della sua energia.
[b]Intercettazione[/b]: quando un missile entra nell'esagono di un nemico (o un nemico entra nel suo), si tira il d10 contro la tabella per velocità relativa e civiltà del missile. Se riesce, missile e bersaglio esplodono; una nave con il campo di forza attivo subisce invece 3 tiri sulla tabella dei colpi (classe 1) o 1 (classe 2). Chi ha il campo di forza spento può provare ad accenderlo all'ultimo istante (d10 ≤ civiltà − 2).
Se l'intercettazione fallisce, quei due non ci riprovano finché restano nello stesso esagono.

[font_size=26][color=#ef6f9c]Rilevamento[/color][/font_size]
Caccia e missili entrano in gioco coperti: il nemico vede solo una freccia. All'inizio della vostra fase di comando si scoprono quelli entro 3 esagoni dalle vostre navi; la ricerca attiva arriva più lontano.

[font_size=26][color=#ef6f9c]Pianeti e asteroidi[/color][/font_size]
Entrando nell'esagono di un pianeta una nave può subito ricevere manovre gratuite (non sotto velocità 1): la parte di movimento già fatta si sottrae dalla nuova velocità. Con velocità 1 nell'esagono del pianeta è [b]in orbita[/b]. Le navi aerodinamiche possono atterrare decelerando a 0. Un missile che entra in un pianeta si distrugge.
Negli asteroidi, a ogni esagono si tira un d10: se non supera la velocità l'unità è colpita (il critico non ha effetto).
"""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if popup:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.82)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.dark_style(8, 0.97))
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 80
	pc.offset_right = -80
	pc.offset_top = 40
	pc.offset_bottom = -40
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	var hh := HBoxContainer.new()
	vb.add_child(hh)
	var t := UI.title("Regole", 44)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(t)
	var back := UI.primary(UI.button("Chiudi" if popup else "Torna al menu", 220, 52, 22))
	back.pressed.connect(func():
		if popup:
			queue_free()
		else:
			main.show_menu())
	hh.add_child(back)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 18)
	sc.add_child(inner)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 21)
	rt.add_theme_font_size_override("bold_font_size", 21)
	rt.text = TEXT
	inner.add_child(rt)
	inner.add_child(UI.title("Tabelle", 34))
	var rt2 := RichTextLabel.new()
	rt2.bbcode_enabled = true
	rt2.fit_content = true
	rt2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt2.add_theme_font_size_override("normal_font_size", 19)
	rt2.add_theme_font_size_override("bold_font_size", 19)
	rt2.add_theme_font_size_override("mono_font_size", 19)
	rt2.text = _tables()
	inner.add_child(rt2)


func _tables() -> String:
	var t := "[color=#ef6f9c][b]Astronavi [4.9][/b][/color]\n[code]"
	t += "%-18s %4s %4s %4s %5s %4s %4s %4s %4s %4s %4s\n" % ["Classe", "Mod", "Var", "Man", "Ener", "Blo", "Bur", "Cor", "CdF", "Civ", "Punt"]
	for k in D.SHIPS:
		var s: Dictionary = D.SHIPS[k]
		t += "%-18s %4d %4d %4d %5d %4d %4d %4d %4d %4d %4d\n" % [s["name"], s["pods"], s["vr"], s["mr"], s["cap"], s["burn"], s["burst"], s["armor"], s["ff"], s["civ"], s["tp"]]
	t += "[/code]\n[color=#ef6f9c][b]Moduli d'armi [5.8][/b][/color] (* = da preparare)\n[code]"
	t += "%-14s %4s %4s %4s %4s %4s %4s %4s %4s\n" % ["Modulo", "NG", "G", "I", "M", "Cmd", "Civ", "Punt", "Fuo"]
	for k in ["hunter", "light", "heavy", "arsenal", "bcomm"]:
		var p: Dictionary = D.PODS[k]
		var cells := []
		for mt in D.MTYPES:
			cells.append(("%d%s" % [p.get(mt, 0), "*" if mt in p.get("prep", []) else ""]))
		t += "%-14s %4s %4s %4s %4s %4d %4d %4d %4d\n" % [p["name"].substr(0, 14), cells[0], cells[1], cells[2], cells[3], p["bcmd"], p.get("civ", 0), p.get("tp", 0), p["fires"]]
	t += "[/code]\n[color=#ef6f9c][b]Risultati del fuoco [8.6][/b][/color] (d10 ≤ valore; A = automatico)\n[code]"
	t += "%-26s %3s %3s %4s %4s %4s %4s %5s %5s\n" % ["Valore del bersaglio", "0", "1", "2-3", "4-5", "6-7", "8-9", "10-11", "12-14"]
	for w in ["lb", "lbb", "pb", "pbb"]:
		var row: Array = D.FIRE[w]["row"]
		var c := []
		for v in row:
			c.append("A" if v >= 99 else ("-" if v == 0 else str(v)))
		t += "%-26s %3s %3s %4s %4s %4s %4s %5s %5s\n" % ["%s (%d u.)" % [D.FIRE[w]["name"], D.FIRE[w]["cost"]], c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]
	t += "[/code]\n[color=#ef6f9c][b]Intercettazione [9.7][/b][/color] (d10 ≤ valore)\n[code]"
	t += "%-12s %3s %4s %4s %4s %5s %4s\n" % ["Civiltà", "0", "1-2", "3-4", "5-7", "8-10", "11+"]
	for civ in [6, 7, 8]:
		var c := []
		for v in D.INTERCEPT[civ]:
			c.append("A" if v >= 99 else str(v))
		t += "%-12s %3s %4s %4s %4s %5s %4s\n" % [str(civ), c[0], c[1], c[2], c[3], c[4], c[5]]
	t += "[/code]\n[color=#ef6f9c][b]Tabella dei colpi [8.7][/b][/color]\n[code]"
	t += "1  colpo critico: chi spara sceglie la parte\n2  ponte o motore (missile: distrutto)\n3  campo di forza o modulo 8\n4  modulo 1 o 9      5  modulo 2 o 10\n6  modulo 3 o 11     7  modulo 4 o 12\n8  modulo 5 o 13     9  modulo 6 o 14\n10 modulo 7 o 15[/code]\n"
	t += "[color=#ef6f9c][b]Missili [9.5][/b][/color] (civiltà: variazione / manovra / energia)\n[code]"
	for mt in ["g", "i", "m"]:
		var parts := []
		for civ in [6, 7, 8]:
			var a: Array = D.MISSILES[mt][civ]
			parts.append("%d: %d/%d/%d" % [civ, a[0], a[1], a[2]])
		t += "%-14s %s\n" % [D.MNAME[mt], "   ".join(parts)]
	t += "[/code]"
	return t
