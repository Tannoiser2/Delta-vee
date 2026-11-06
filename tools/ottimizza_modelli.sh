#!/usr/bin/env bash
# Alleggerisce i modelli 3D fatti con Meshy (decine di MB l'uno) per il web:
# semplifica la geometria a un numero di triangoli fissato per nave, porta la texture a 1024 px
# e la converte in JPEG. Richiede Node.js: npm i @gltf-transform/cli sharp
# Uso: tools/ottimizza_modelli.sh <cartella con i .glb originali> [cartella di uscita]
set -euo pipefail
SRC="$1"
OUT="${2:-assets/models}"
GT="${GLTF_TRANSFORM:-npx gltf-transform}"
TMP="$(mktemp -d)"
mkdir -p "$OUT"
# nome del file originale : nome nel gioco : triangoli voluti
for pair in "Piccolo:Piccolo:14000" "Sword:Sword:18000" "Spear:Spear:18000" "Dagger:Dagger:14000" \
	"Flute:Flute:16000" "Clarinet:Clarinet:20000" "Corco Gamma:Gamma:18000" "Corco Zeta:Zeta:20000" \
	"Corco Iota:Iota:22000" "Corco Mu:Mu:26000" "Terwillicker-X:TX:9000" "Missile:missile:4000"; do
	IFS=: read -r src dst tgt <<< "$pair"
	orig=$($GT inspect "$SRC/$src.glb" --format csv 2>/dev/null | grep TRIANGLES | head -1 | cut -d, -f5)
	r=$(python3 -c "print(round($tgt/$orig, 5))")
	$GT optimize "$SRC/$src.glb" "$TMP/a.glb" --compress false --simplify-ratio "$r" --simplify-error 0.01 --texture-compress false
	$GT resize "$TMP/a.glb" "$TMP/b.glb" --width 1024 --height 1024
	$GT jpeg "$TMP/b.glb" "$OUT/$dst.glb" --quality 85
	echo "$dst: $(stat -c %s "$OUT/$dst.glb") byte"
done
rm -rf "$TMP"
# In Godot le texture estratte (*_0.jpg) vanno importate con compressione "Lossy" (vedi i .import).
# Orientamento, stazza e posizione degli ugelli dei motori: MODELS in scripts/ui/board_3d.gd.
