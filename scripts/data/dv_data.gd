extends RefCounted
## Dati del gioco DeltaVee (SPI, 1981): classi delle astronavi, moduli (pod), missili, tabelle e scenari.
## Tutti i numeri vengono dalle tabelle del regolamento (pagina 8) e dagli scenari (pagine 15-16).

# ------------------------------------------------------------------ astronavi [4.9]
# pods, velocità (VR), manovra (MR), energia, consumo (blocco), aerodinamica, burster, corazza,
# campo di forza, livello di civiltà, programma di puntamento
const SHIPS := {
	"T5000":    {"name": "Terwillicker-5000", "pods": 0, "vr": 2, "mr": 7, "cap": 15, "burn": 1, "stream": true, "burst": 1, "armor": 1, "ff": 0, "civ": 7, "tp": -2, "bc": true},
	"TX":       {"name": "Terwillicker-X", "pods": 0, "vr": 3, "mr": 9, "cap": 15, "burn": 1, "stream": true, "burst": 2, "armor": 2, "ff": 0, "civ": 8, "tp": -4, "bc": true},
	"Dagger":   {"name": "Dagger", "pods": 2, "vr": 2, "mr": 6, "cap": 48, "burn": 4, "stream": true, "burst": 2, "armor": 2, "ff": 1, "civ": 8, "tp": -4},
	"Sword":    {"name": "Sword", "pods": 5, "vr": 3, "mr": 8, "cap": 78, "burn": 6, "stream": false, "burst": 2, "armor": 2, "ff": 2, "civ": 8, "tp": -4},
	"Spear":    {"name": "Spear", "pods": 8, "vr": 1, "mr": 4, "cap": 144, "burn": 12, "stream": false, "burst": 2, "armor": 2, "ff": 2, "civ": 8, "tp": -4},
	"Piccolo":  {"name": "Piccolo", "pods": 1, "vr": 3, "mr": 8, "cap": 30, "burn": 3, "stream": true, "burst": 1, "armor": 1, "ff": 0, "civ": 7, "tp": -2},
	"Flute":    {"name": "Flute", "pods": 4, "vr": 3, "mr": 6, "cap": 66, "burn": 6, "stream": true, "burst": 1, "armor": 2, "ff": 1, "civ": 8, "tp": -4},
	"Clarinet": {"name": "Clarinet", "pods": 7, "vr": 2, "mr": 7, "cap": 104, "burn": 8, "stream": false, "burst": 1, "armor": 1, "ff": 0, "civ": 8, "tp": -4},
	"Gamma":    {"name": "Corco Gamma", "pods": 3, "vr": 1, "mr": 4, "cap": 54, "burn": 6, "stream": true, "burst": 1, "armor": 0, "ff": 0, "civ": 7, "tp": -2},
	"Zeta":     {"name": "Corco Zeta", "pods": 6, "vr": 1, "mr": 3, "cap": 80, "burn": 8, "stream": false, "burst": 1, "armor": 0, "ff": 0, "civ": 6, "tp": 0},
	"Iota":     {"name": "Corco Iota", "pods": 9, "vr": 2, "mr": 5, "cap": 120, "burn": 12, "stream": false, "burst": 1, "armor": 1, "ff": 1, "civ": 7, "tp": -4},
	"Mu":       {"name": "Corco Mu", "pods": 12, "vr": 1, "mr": 4, "cap": 176, "burn": 16, "stream": false, "burst": 1, "armor": 0, "ff": 0, "civ": 7, "tp": -2},
}

# ------------------------------------------------------------------ moduli [5.8]
# lp = armi laser/particelle; ug/g/i/m = missili non guidati, guidati, intelligenti, MIMS;
# prep = tipi che vanno preparati; bcmd = comandi di battaglia; fires = fuochi per fase
const PODS := {
	"hunter":   {"name": "Cacciatore", "short": "Cacc.", "lp": true, "ug": 2, "g": 0, "i": 1, "m": 0, "prep": [], "bcmd": 0, "civ": 8, "tp": -4, "jump": true, "fires": 1, "armor": 2},
	"light":    {"name": "Armi leggere", "short": "Leggere", "lp": true, "ug": 5, "g": 3, "i": 0, "m": 0, "prep": ["ug", "g"], "bcmd": 1, "civ": 6, "tp": -2, "jump": false, "fires": 1, "armor": 1},
	"heavy":    {"name": "Armi pesanti", "short": "Pesanti", "lp": true, "ug": 6, "g": 5, "i": 3, "m": 1, "prep": ["g", "i", "m"], "bcmd": 1, "civ": 7, "tp": -4, "jump": false, "fires": 1, "armor": 2},
	"arsenal":  {"name": "Arsenale", "short": "Arsenale", "lp": true, "ug": 8, "g": 7, "i": 5, "m": 2, "prep": ["i", "m"], "bcmd": 1, "civ": 8, "tp": -4, "jump": false, "fires": 2, "armor": 2},
	"bcomm":    {"name": "Comunicazioni di battaglia", "short": "Com. batt.", "lp": false, "bcmd": 2, "civ": 8, "tp": -6, "jump": false, "fires": 0, "armor": 1},
	"tractor":  {"name": "Raggio traente", "short": "Traente", "lp": false, "bcmd": 0, "civ": 7, "jump": false, "fires": 0},
	"bcpod":    {"name": "Hangar del caccia", "short": "Hangar", "lp": false, "bcmd": 0, "jump": false, "fires": 0},
	"jump":     {"name": "Salto standard", "short": "Salto", "lp": false, "bcmd": 0, "civ": 7, "jump": true, "fires": 0},
	"ajump":    {"name": "Salto potenziato", "short": "Salto pot.", "lp": false, "bcmd": 0, "civ": 8, "jump": true, "fires": 0},
	"energy":   {"name": "Energia", "short": "Energia", "lp": false, "bcmd": 0, "jump": false, "fires": 0},
	"crew":     {"name": "Equipaggio", "short": "Equip.", "lp": false, "bcmd": 0, "jump": false, "fires": 0},
	"cabin":    {"name": "Cabine passeggeri", "short": "Cabine", "lp": false, "bcmd": 0, "jump": false, "fires": 0},
	"support":  {"name": "Supporto vitale", "short": "Supporto", "lp": false, "bcmd": 0, "jump": false, "fires": 0},
	"cargo":    {"name": "Stiva", "short": "Stiva", "lp": false, "bcmd": 0, "jump": false, "fires": 0, "cargo": true},
	"bcargo":   {"name": "Stiva schermata", "short": "Stiva sch.", "lp": false, "bcmd": 0, "jump": false, "fires": 0, "cargo": true},
	"equip":    {"name": "Attrezzature", "short": "Attrezz.", "lp": false, "bcmd": 0, "jump": false, "fires": 0},
}

const MTYPES := ["ug", "g", "i", "m"]
const MNAME := {"ug": "non guidato", "g": "guidato", "i": "intelligente", "m": "MIMS"}
const MNAME_FULL := {"ug": "Missile non guidato", "g": "Missile guidato", "i": "Missile intelligente", "m": "MIMS"}
## nome della pedina originale per tipo di missile
const MFILE := {"ug": "unguided", "g": "guided", "i": "intelligent", "m": "mims"}

# ------------------------------------------------------------------ missili [9.5]
# per livello di civiltà: [velocità, manovra, unità di energia]
const MISSILES := {
	"g": {6: [1, 5, 7], 7: [2, 5, 9], 8: [2, 6, 10]},
	"i": {6: [2, 5, 6], 7: [2, 6, 7], 8: [2, 7, 9]},
	"m": {6: [2, 6, 6], 7: [2, 6, 6], 8: [2, 7, 7]},
}

# ------------------------------------------------------------------ tabelle
## [8.3] velocità relativa: righe = velocità del bersaglio (0-1, 2…9), colonne = velocità di chi spara
const REL_VEL := [
	[1, 2, 3, 4, 5, 6, 7, 8, 9],
	[2, 3, 4, 4, 5, 6, 7, 8, 9],
	[3, 4, 4, 5, 6, 7, 8, 9, 9],
	[4, 4, 5, 6, 6, 7, 8, 9, 10],
	[5, 5, 6, 6, 7, 8, 9, 9, 10],
	[6, 6, 7, 7, 8, 8, 9, 10, 11],
	[7, 7, 8, 8, 9, 9, 10, 11, 11],
	[8, 8, 9, 9, 9, 10, 11, 11, 12],
	[9, 9, 9, 10, 10, 11, 11, 12, 13],
]

## [8.6] tipi di fuoco: costo in unità di energia e probabilità per valore del bersaglio
## colonne: 0, 1, 2-3, 4-5, 6-7, 8-9, 10-11, 12-14 (A = automatico = 99, - = 0)
const FIRE := {
	"lb":  {"name": "Raffica laser", "art": "una raffica laser", "cost": 0, "row": [7, 6, 5, 4, 3, 2, 1, 0]},
	"lbb": {"name": "Sbarramento laser", "art": "uno sbarramento laser", "cost": 2, "row": [9, 8, 7, 6, 5, 4, 3, 1]},
	"pb":  {"name": "Raffica di particelle", "art": "una raffica di particelle", "cost": 1, "row": [99, 9, 7, 4, 1, 0, 0, 0]},
	"pbb": {"name": "Sbarramento di particelle", "art": "uno sbarramento di particelle", "cost": 3, "row": [99, 99, 9, 7, 4, 1, 0, 0]},
}

static func fire_col(tv: int) -> int:
	if tv <= 0:
		return 0
	if tv == 1:
		return 1
	if tv <= 3:
		return 2
	if tv <= 5:
		return 3
	if tv <= 7:
		return 4
	if tv <= 9:
		return 5
	if tv <= 11:
		return 6
	if tv <= 14:
		return 7
	return -1

## [9.7] intercettazione: per livello di civiltà, colonne velocità relativa 0, 1-2, 3-4, 5-7, 8-10, 11+
const INTERCEPT := {6: [8, 6, 4, 2, 1, 1], 7: [9, 7, 5, 3, 2, 1], 8: [99, 8, 6, 4, 3, 2]}

static func icol(rv: int) -> int:
	if rv <= 0:
		return 0
	if rv <= 2:
		return 1
	if rv <= 4:
		return 2
	if rv <= 7:
		return 3
	if rv <= 10:
		return 4
	return 5

## [8.7] tabella dei colpi: per risultato del dado le due parti colpite (1 = colpo critico)
const HIT_TABLE := {
	2: ["bridge", "engine"], 3: ["ff", "p8"], 4: ["p1", "p9"], 5: ["p2", "p10"], 6: ["p3", "p11"],
	7: ["p4", "p12"], 8: ["p5", "p13"], 9: ["p6", "p14"], 10: ["p7", "p15"],
}

const PART_NAMES := {"bridge": "ponte", "engine": "motore", "ff": "campo di forza"}

## nomi dei lati
const SIDE_NAMES := ["Giocatore 1", "Giocatore 2"]
const SIDE_FILE := ["o", "g"]   # pedine arancioni e verdi
const SIDE_COL := ["arancione", "verde"]

# ------------------------------------------------------------------ scenari [11.0]
# Ogni mappa misura 16 colonne × 18 righe; le mappe dello scenario sono affiancate da sinistra a
# destra (A, B, C, …). La sigla di un esagono è mappa + colonna + riga, come sul tabellone: A0207.
const MAP_COLS := 16
const MAP_ROWS := 18

const SCENARIOS := [
	{
		"name": "Il duello", "orig": "The Showdown",
		"text": "Una banda di tagliagole fugge su un inseguitore a lungo raggio rubato a un'installazione federale; lo intercetta un'astronave gemella della guardia locale. I militari, furiosi per il furto, ordinano di distruggere i criminali.",
		"maps": ["A", "B"],
		"sides": ["I tagliagole", "La guardia locale"],
		"win": "Vince chi distrugge per primo l'astronave avversaria. Nessuno può saltare nell'iperspazio.",
		"forces": [
			[{"id": "E", "cls": "Piccolo", "pods": [["hunter", 2]], "hex": "A0207", "dir": 3, "v": 1}],
			[{"id": "D", "cls": "Piccolo", "pods": [["hunter", 2]], "hex": "B1511", "dir": 9, "v": 1}],
		],
	},
	{
		"name": "Il primo colpo", "orig": "The First Shot",
		"text": "Tensione alle stelle fra Venable e Laidley, due pianeti del sistema di Eridani. Un incrociatore leggero di Venable si spinge nello spazio di Laidley «per tastare il terreno» e incontra due pattugliatori: le navi più piccole aprono il fuoco e comincia la breve Guerra di Eridani.",
		"maps": ["A"],
		"sides": ["Incrociatore di Venable", "Pattuglia di Laidley"],
		"win": "Il Giocatore 1 vince se distrugge entrambi i Dagger; il Giocatore 2 se distrugge lo Sword. Se tutte le unità avversarie sono a più di 25 esagoni di distanza, è pareggio.",
		"forces": [
			[{"id": "A", "cls": "Sword", "pods": [["heavy", 2], ["heavy", 2], ["bcomm", 2], ["bcpod", 2, "TX"], ["energy", 2]], "hex": "A1112", "dir": 9, "v": 3}],
			[{"id": "A", "cls": "Dagger", "pods": [["heavy", 2], ["energy", 2]], "hex": "A0706", "dir": 3, "v": 3},
			 {"id": "B", "cls": "Dagger", "pods": [["heavy", 2], ["energy", 2]], "hex": "A0705", "dir": 3, "v": 3}],
		],
	},
	{
		"name": "Fuga da Tau Ceti", "orig": "Escape from Tau Ceti",
		"text": "Quattro navi di contrabbandieri lasciano il sistema di Tau Ceti con un carico di droghe micidiali e di evasi; un incrociatore pesante federale si lancia all'inseguimento con l'ordine di impedire il salto nell'iperspazio a ogni costo.",
		"maps": ["A", "B", "C", "D"],
		"sides": ["I contrabbandieri", "L'incrociatore federale"],
		"win": "Il Giocatore 1 vince se il Corco Iota o due Corco Gamma saltano nell'iperspazio (solo dalla mappa E, a destra della D, o dalle mappe sopra e sotto di essa), oppure se distrugge lo Sword. Il Giocatore 2 vince se distrugge tre navi nemiche, Iota compreso.",
		"jump_from": 4,
		"forces": [
			[{"id": "A", "cls": "Iota", "pods": [["heavy", 2, "noim"], ["heavy", 2, "noim"], ["energy", 2], ["jump", 2], ["crew", 2], ["bcargo", 2], ["bcargo", 2], ["bcargo", 2], ["bcargo", 2]], "near": "A0909", "dir": 3, "v": 2, "spent": 3},
			 {"id": "B", "cls": "Gamma", "pods": [["light", 1], ["jump", 1], ["cargo", 1]], "near": "A0909", "dir": 3, "v": 2, "spent": 3},
			 {"id": "C", "cls": "Gamma", "pods": [["light", 1], ["jump", 1], ["cargo", 1]], "near": "A0909", "dir": 3, "v": 2, "spent": 3},
			 {"id": "D", "cls": "Gamma", "pods": [["jump", 0], ["crew", 0], ["cargo", 0]], "near": "A0909", "dir": 3, "v": 2, "spent": 3}],
			[{"id": "A", "cls": "Sword", "pods": [["arsenal", 2], ["arsenal", 2], ["bcomm", 2], ["bcpod", 2, "TX"], ["bcpod", 2, "TX"]], "column": "A01", "dir": -1, "v": 3}],
		],
	},
	{
		"name": "Pirati!", "orig": "Pirates!",
		"text": "Un Corco Mu carico di passeggeri e merci preziose si avvicina al pianeta Esata dopo il salto nel sistema. Vicino alla fitta Cintura di Bicker lo assalgono due spietate navi pirata in cerca di bottino: parte una richiesta d'aiuto verso Esata.",
		"maps": ["A", "B", "C"],
		"sides": ["Il Corco Mu e la scorta", "I pirati"],
		"win": "Il Giocatore 1 vince appena il Corco Mu entra in orbita attorno a Esata (nel suo esagono a velocità 1) o se distrugge entrambi i Flute. Se il Corco Mu viene distrutto è pareggio. Il Giocatore 2 vince se un Flute si aggancia al Corco Mu (stesso esagono, velocità e direzione, comando Aggancio).",
		"planet": ["A0409"],
		"planet_name": "Esata",
		"asteroids": ["C0902", "C0904", "C0907", "C0909", "C0912", "C0915"],
		"forces": [
			[{"id": "B", "cls": "Mu", "pods": [["light", 1], ["bcpod", 1, "T5000"], ["jump", 1], ["energy", 1], ["support", 1], ["cabin", 1], ["cabin", 1], ["cabin", 1], ["crew", 1], ["bcargo", 1], ["bcargo", 1], ["bcargo", 1]], "hex": "C1406", "dir": 9, "v": 2},
			 {"id": "A", "cls": "Dagger", "pods": [["heavy", 2], ["energy", 2]], "hex": "A0409", "dir": 3, "v": 1, "unalerted": true}],
			[{"id": "A", "cls": "Flute", "pods": [["arsenal", 2], ["energy", 2], ["tractor", 2], ["bcargo", 2]], "hex": "B1612", "dir": -1, "v": 0},
			 {"id": "B", "cls": "Flute", "pods": [["heavy", 2], ["bcpod", 2, "TX"], ["energy", 2], ["bcargo", 2]], "hex": "B1611", "dir": -1, "v": 0}],
		],
	},
	{
		"name": "Attacco al Convoglio Rosso", "orig": "Attack on Convoy Red",
		"text": "Un convoglio vitale di armi e munizioni, organizzato in fretta dalla flotta imperiale e dai mercanti, punta sul pianeta Zaraznov dopo il salto da un sistema vicino. Una rivolta riuscita ha dato agli insorti il controllo di una piccola flotta ben armata, che pattuglia lo spazio di Zaraznov in attesa del convoglio.",
		"maps": ["A", "B", "C"],
		"sides": ["Il Convoglio Rosso", "Gli insorti"],
		"win": "Giocatore 1: 1 punto per ogni nave messa in orbita attorno a Zaraznov (poi esce di gioco) più 1 per ogni stiva intatta a bordo; vince a 8 punti. Giocatore 2: 1 punto per ogni nave nemica distrutta e per ogni stiva distrutta, -2 per ogni Flute perso; vince a 8 punti, ma perde subito se il Clarinet viene distrutto.",
		"planet": ["C1110"],
		"planet_name": "Zaraznov",
		"group_choice": [[0, 4], [0, 6]],
		"forces": [
			[{"id": "A", "cls": "Spear", "pods": [["arsenal", 2], ["arsenal", 2], ["bcomm", 2], ["bcpod", 2, "TX"], ["tractor", 2, 8], ["jump", 2], ["energy", 2], ["crew", 2]], "near": "A0407", "spent": 10},
			 {"id": "B", "cls": "Zeta", "pods": [["light", 1], ["energy", 1], ["jump", 1], ["cargo", 1], ["cargo", 1], ["cargo", 1]], "near": "A0407", "spent": 10},
			 {"id": "C", "cls": "Zeta", "pods": [["light", 1], ["energy", 1], ["jump", 1], ["cargo", 1], ["cargo", 1], ["cargo", 1]], "near": "A0407", "spent": 10},
			 {"id": "D", "cls": "Zeta", "pods": [["light", 1, "nog"], ["energy", 1], ["jump", 1], ["cargo", 1], ["cargo", 1], ["cargo", 1]], "near": "A0407", "spent": 10},
			 {"id": "E", "cls": "Dagger", "pods": [["hunter", 2], ["energy", 2]], "near": "A0407", "spent": 10}],
			[{"id": "A", "cls": "Clarinet", "pods": [["heavy", 2], ["heavy", 2], ["bcomm", 2], ["bcpod", 2, "TX"], ["bcpod", 2, "TX"], ["energy", 2], ["crew", 2]], "hex": "B0717"},
			 {"id": "B", "cls": "Flute", "pods": [["heavy", 2], ["bcpod", 2, "TX"], ["energy", 2], ["equip", 2]], "hex": "B0617"},
			 {"id": "C", "cls": "Flute", "pods": [["light", 2], ["tractor", 2, 8], ["energy", 2], ["crew", 2]], "hex": "B0816"}],
		],
	},
]

const DIR_NAMES := ["12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"]
