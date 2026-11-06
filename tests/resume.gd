extends SceneTree
## Controlla il salvataggio: una partita IA contro IA viene rigiocata dalle decisioni registrate
## (tutte, o solo la prima metà e poi di nuovo con l'IA) e deve dare lo stesso diario.
## Uso: godot --headless --path . -s tests/resume.gd

var fails := 0


func _init() -> void:
	_run()


func _cfg(scn: int, seed_v: int) -> Dictionary:
	return {"scenario": scn, "seats": [{"name": "", "ai": true, "level": 1}, {"name": "", "ai": true, "level": 1}],
		"seed": seed_v, "max_turns": 30}


func _engine(cfg: Dictionary) -> DVEngine:
	var eng := DVEngine.new()
	eng.headless = true
	root.add_child(eng)
	eng.setup(cfg)
	eng.ais[0] = DVAI.new(1, 11)
	eng.ais[1] = DVAI.new(1, 12)
	return eng


func _run() -> void:
	await process_frame
	for scn in 5:
		var a := _engine(_cfg(scn, 500 + scn))
		await a.run()
		# 1) tutte le decisioni: stessa partita
		var c := _cfg(scn, 500 + scn)
		c["dec"] = a.dec_log.duplicate()
		var b := _engine(c)
		await b.run()
		var same := b.fingerprint() == a.fingerprint() and b.log_lines == a.log_lines and str(b.stats) == str(a.stats)
		if not same:
			for i in mini(a.log_lines.size(), b.log_lines.size()):
				if a.log_lines[i] != b.log_lines[i]:
					print("  diverge alla riga %d:\n   A: %s\n   B: %s" % [i, a.log_lines[i], b.log_lines[i]])
					print("   prima: ", a.log_lines.slice(maxi(0, i - 4), i))
					break
		# 2) metà delle decisioni, poi l'IA (deve ripartire senza errori e coincidere fino a quel punto)
		var c2 := _cfg(scn, 500 + scn)
		var half := a.dec_log.size() / 2
		c2["dec"] = a.dec_log.slice(0, half)
		var d := _engine(c2)
		var at_resume := [-1]
		d.resumed.connect(func(): at_resume[0] = d.log_lines.size())
		await d.run()
		var prefix_ok: bool = at_resume[0] > 0 and d.log_lines.slice(0, at_resume[0]) == a.log_lines.slice(0, at_resume[0])
		print("Scenario %d: decisioni %d, rigiocata identica %s, ripresa a metà %s (turno finale %d), statistiche %s" % [
			scn + 1, a.dec_log.size(), same, prefix_ok, d.turn, a.stats])
		if not same or not prefix_ok:
			fails += 1
		for e in [a, b, d]:
			e.queue_free()
	print("ESITO: %s" % ("tutto bene" if fails == 0 else "%d errori" % fails))
	quit()
