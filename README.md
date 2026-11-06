# DeltaVee — versione digitale (Godot 4)

Versione digitale di **DeltaVee**, il «Tactical Space Combat System» per il gioco di ruolo **Universe**
(John H. Butterfield, Simulations Publications Inc., 1981). Pedine originali e copertina dal modulo
Tabletop Simulator; tema «SPI 1981»: lo spazio nero con la griglia esagonale arancione del tabellone,
il giallo del logo e le schede chiare degli Spaceship Log. Caratteri liberi (OFL): Righteous per i
titoli, Saira Condensed per testi e tabelle, Share Tech Mono per il diario di bordo.

La pubblicazione non parte da sola: Actions → **Pubblica** → *Run workflow*
(ludoteca privata su `deltavee.ludoteca-digitale.com` con i segreti Cloudflare, e GitHub Pages finché il
repository è pubblico).

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **Tutte le regole** del regolamento (sezioni 1-11): sequenza a sei fasi, movimento newtoniano nelle
  12 direzioni (zig-zag verso i vertici, con il passo ricordato fra un turno e l'altro), mappe aggiunte
  quando si esce dal bordo, comandi di manovra (accelera, decelera, vira, scarto laterale, salto) con il
  consumo di energia a blocchi e unità, comandi di battaglia (prepara missile, guida missile, ricerca
  attiva, prepara/lancia/fai rientrare i caccia, raggio traente, campo di forza, aggancio), rilevamento
  delle pedine coperte, fuoco laser e di particelle con velocità relativa, linea di rotta, puntamento e
  comunicazioni di battaglia, tabella dei colpi con le parti a scelta e le corazze V/D/X, effetti dei danni,
  missili non guidati, guidati, intelligenti e MIMS, intercettazione (anche fra missili) con attivazione
  d'emergenza del campo di forza, pianeti (manovre gratuite, orbita, atterraggio) e asteroidi.
- **I cinque scenari**: Il duello, Il primo colpo, Fuga da Tau Ceti (con la mappa E e il salto),
  Pirati! (il Dagger da allertare, Esata e la Cintura di Bicker, l'aggancio), Attacco al Convoglio Rosso
  (punti vittoria e orbita attorno a Zaraznov).
- **Due lati**, ognuno persona o IA (facile, normale, difficile); con due persone allo stesso schermo si gioca
  a turno. L'IA guarda un passo avanti con precisione e qualche turno più in là per gli obiettivi
  dello scenario. Lanci e manovre dei missili sono calcolati con esattezza (fino al loro movimento il
  nemico fa solo il suo prossimo movimento, già noto); ogni nave evita gli esagoni che i missili nemici
  possono raggiungere. **Suggerisci** propone gli ordini o il colpo dell'IA, che si possono modificare.
- **Mappa 2D** come il tabellone (sigle degli esagoni, logo e rosa delle direzioni) e **tabellone 3D**
  girevole con i modelli 3D delle astronavi (fatti con Meshy, in
  `assets/models/`), missili, pianeti e asteroidi. Si passa dall'una all'altro con **2D / 3D**.
  - Le navi rispettano la stazza: dal Terwillicker (0 moduli, quasi un caccia, poco più di un esagono;
    lo stesso modello serve per il 5000, per l'X e per i caccia) al Corco Mu (12 moduli, tre esagoni e mezzo).
    Il missile ha un modello unico.
  - Niente pedina sotto i modelli: un'asta trasparente scende fino a un cerchietto del colore del lato a
    livello dell'esagono; le unità nello stesso esagono si impilano in altezza.
  - Dietro gli ugelli c'è il getto dei motori, più lungo con la velocità e con la potenza (manovra) della
    nave; si spegne se il motore è distrutto. I missili hanno un getto arancione.
  - Il secondo lato ha lo scafo grigio-verde e le strisce verdi al posto di quelle rosse.
- **Opacità della griglia**: il cursore **Griglia** in alto regola la griglia di esagoni in 2D e in 3D; a zero
  restano solo i puntini al centro degli esagoni. La scelta resta salvata.
  - `tools/ottimizza_modelli.sh` rifà i modelli leggeri dagli originali (da 24-83 MB a circa 1 MB l'uno);
    `tests/galleria3d_shot.gd` e `tests/navi3d_shot.gd` li fotografano.
- **Scheda dell'unità** come lo Spaceship Log: compartimenti con V/D/X, energia, missili per modulo,
  caccia, comandi di battaglia.
- **Replay finale** continuo e simultaneo: in ogni turno tutte le unità dei due lati si muovono insieme,
  ciascuna alla sua velocità, mentre laser, particelle e missili partono in tempo reale dalle navi in
  movimento; pausa, velocità ½×-4× e cursore; funziona in 2D e in 3D (`scripts/ui/replay.gd`).
- **Effetti diversi per ogni tipo di fuoco**: raffica laser (un dardo rosso), sbarramento laser (cinque dardi
  a raffica), raffica di particelle (un globo di plasma con la scia), sbarramento di particelle (tre globi che
  convergono legati da fulmini); impatti con scintille, esplosioni con lampo, palla di fuoco, onda d'urto,
  detriti e fumo (`scripts/ui/fx2d.gd` e `board_3d.gd`).
- **Illustrazioni** delle 12 classi di astronavi, dei caccia, dei missili e dei 23 moduli: nel menu, nella scheda
  dell'unità (stile Spaceship Log illustrato, `scripts/ui/ship_card.gd`), nel fuoco e nelle regole.
- **Scritte di combattimento** sulla mappa (2D e 3D), in partita e nel replay: "mancato", "di striscio",
  "CRITICO!", la parte colpita e il suo stato, "INTERCETTATO!", "DISTRUTTO!".
- **Suoni** sintetizzati per ogni tipo di fuoco, missili, intercettazioni, impatti, esplosioni, motori e salto
  (`tools/genera_suoni.py` li rigenera in `assets/audio/`); il pulsante **Audio sì/no** li spegne e la scelta
  resta salvata.
- **Segui l'azione** nel replay: la telecamera accompagna le unità che si muovono e sparano (si può
  spegnere per guardare la mappa liberamente).
- **Fine per stallo**: se le flotte si separano (nessun colpo a segno per 6 turni con le navi nemiche più
  vicine a oltre 10 esagoni e senza avvicinarsi) o nessuno colpisce più per 10 turni (navi alla deriva con il
  motore distrutto), la partita finisce: pareggio, o ai punti nell'Attacco al Convoglio Rosso. Le navi che
  devono entrare in orbita virano subito verso il pianeta invece di restare alla deriva.
- **Tre livelli d'IA** davvero diversi: la facile pianifica poco e non zigzaga, la difficile valuta più
  rotte e più varianti. Nello scenario Pirati! l'IA dei pirati evita di colpire il Corco Mu con i propri
  missili (distruggerlo darebbe il pareggio).
- **Pannello a schede** a destra: in alto, sempre visibili, l'immagine intera dell'unità, il nome, la
  posizione e l'energia; sotto, le schede **Ordini** (comandi della fase), **Caratteristiche** (valori e
  scafo) e **Moduli** (i moduli con le loro immagini; un tocco ne mostra la descrizione). I pulsanti di
  fine fase restano sempre in fondo e nessuna scheda deve scorrere (`tests/pannello_shot.gd` lo controlla).
- **Battaglia libera e cantiere navale** (sesto scenario): il regolamento non prevede la costruzione delle
  flotte (le navi e i moduli sono sempre fissati dagli scenari), quindi il **Cantiere navale** è un'aggiunta:
  - si scelgono fino a 6 astronavi per lato fra le 12 classi, e per ogni nave i moduli (armi leggere, pesanti,
    arsenale, cacciatore, comunicazioni, hangar con Terwillicker-X o 5000, energia, raggio traente, salto,
    equipaggio, stive...), la corazza di ciascuno e il nome della flotta;
  - punti per bilanciare (scafo dai valori della tabella 4.9, moduli secondo armi, missili e corazza), con un
    tetto facoltativo di 100, 200 o 300 punti e la flotta casuale entro il tetto;
  - terreno (spazio aperto, pianeta, asteroidi), distanza e velocità di partenza;
  - vince chi distrugge tutte le navi nemiche; altrimenti, a fine partita, chi ha più punti (navi e moduli
    nemici distrutti). Si gioca anche online e si salva come le altre partite (`scripts/ui/shipyard.gd`,
    `tests/libera_sim.gd`, `tests/cantiere_shot.gd`).
- **Tutorial** guidato sul primo scenario (pulsante **Tutorial** nel menu): spiega pedine, movimento
  newtoniano, fase di comando, fase di fuoco, missili e danni man mano che capitano, e mette in evidenza
  i pulsanti da usare (`scripts/ui/tutor.gd`).
- **Salvataggio automatico**: ogni partita locale viene salvata dopo ogni decisione (`user://partita.json`).
  Uscendo al menu compare **Partita in sospeso** con **Riprendi**: la partita viene rigiocata dalle decisioni
  registrate e riparte esattamente da dove era rimasta. Il salvataggio sparisce a fine partita.
- **Statistiche di fine partita**: confronto a barre fra i due lati (colpi sparati e a segno, critici, parti
  danneggiate, missili lanciati, intercettazioni, missili abbattuti, unità distrutte e perdute, energia
  spesa, esagoni percorsi) e l'unità migliore di ogni lato.
- **Regole** riassunte in italiano con tutte le tabelle, dal menu e in partita.

## Comandi
- Mappa 2D: trascina per spostare, rotella (o due dita) per lo zoom. **Centra** rifà l'inquadratura.
- Tabellone 3D: trascina per ruotare, tasto destro (o Maiusc + trascina) per spostare, rotella per lo zoom.
- Tocca una pedina per vederne la scheda (più pedine nello stesso esagono: tocca di nuovo).
- Fase di comando: scegli l'unità nella striscia in alto a destra, poi velocità (meno, più), direzione (Vira sx / Vira dx),
  scarto (tocca l'esagono azzurro) e comandi di battaglia. La linea gialla è il prossimo movimento.
- Fase di fuoco: scegli unità e arma, poi il bersaglio sulla mappa (la percentuale è la probabilità di
  colpire) e **FUOCO!**; per i missili scegli l'esagono di lancio, la direzione e la velocità.

## Gioco online
Dal menu, **Gioca online** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(Realtime Database), con le stanze sotto `deltavee/rooms`: la sezione generica `$game` delle regole del
database (già pubblicata con Titans, El Grande e Ghouls) lo copre, non serve toccare le regole.

- **Chi crea la stanza** sceglie scenario e opzioni nel menu, scrive il nome, sceglie quale lato gioca,
  preme *Crea una stanza* e comunica il codice di 4 lettere. Quando l'amico è entrato preme *Inizia online*.
- **L'amico** scrive il nome e il codice e preme *Entra*.
- Ogni decisione è una mossa numerata nel database: i due dispositivi fanno girare lo stesso motore con lo
  stesso seme, quindi la partita è identica. Se cade la linea si rientra con lo stesso codice; se un giocatore
  tace per un minuto, al suo posto gioca l'IA finché non rientra.

## Interpretazioni
Dove il regolamento lascia spazio, la versione digitale fa così:
- i moduli sono assegnati alle caselle del log nell'ordine dello scenario;
- l'attivazione d'emergenza del campo di forza riesce con d10 ≤ civiltà − 2 («più di uno sotto la civiltà»);
- un missile di civiltà 8 intercetta sempre (non si chiede ogni volta se rinunciare);
- lo scenario 5 finisce anche quando non resta in gioco nessuna nave del convoglio (vince chi ha più punti);
- c'è un limite di turni a scelta (20-60): raggiunto, la partita è pari (nello scenario 5 vince chi ha più punti).

## Struttura
- `scripts/core/engine.gd` — motore delle regole (senza grafica), `hex.gd` — geometria della griglia,
  `ai.gd` — l'IA.
- `scripts/data/dv_data.gd` — astronavi, moduli, missili, tabelle e scenari.
- `scripts/ui/` — menu, partita, mappa 2D, tabellone 3D, `timeline.gd` (animazioni e replay), regole.
- `scripts/net/` — Firebase e partita online in lockstep.
- `assets/counters/` — le pedine originali, estratte dal modulo TTS con `tools/estrai_pedine.py`.
- `tests/sim.gd` — partite IA contro IA senza grafica:
  `godot --headless --path . -s tests/sim.gd -- 0 4 1` (tutti gli scenari, 4 partite, IA normale).
- `tests/online_play.gd` + `tests/firebase_mock.py` — partita online completa fra due istanze su un
  finto Firebase locale.
- `tests/shot.gd`, `replay_shot.gd`, `fx_shot.gd` — fotografie dell'interfaccia, del replay e degli
  effetti (serve un display, anche virtuale).
- `tests/resume.gd` — controlla che una partita ripresa dalle decisioni salvate sia identica all'originale;
  `tests/novita_shot.gd` — foto e controlli di tutorial, partita salvata e statistiche.
- `tools/controlla_glifi.py` — controlla che ogni carattere usato nei testi esista in tutti i font
  (altrimenti sul web comparirebbe un quadratino).
- Pubblicazione: solo a mano (Actions, *Run workflow*) o con un commit che contiene `[pubblica]`;
  il workflow pubblica su GitHub Pages e su Cloudflare (`tools/pubblica_cloudflare.py`).
