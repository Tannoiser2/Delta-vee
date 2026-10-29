"""Estrae le pedine dal modulo Tabletop Simulator di DeltaVee (SPI, 1981).

Uso: python3 tools/estrai_pedine.py <cartella Mods del modulo> <cartella di uscita>

Per ogni pedina legge colore (arancio = Giocatore 1, verde = Giocatore 2), tipo (dalla scritta in alto)
e sigla (in basso) con tesseract, e salva fronte e retro come <lato>_<tipo>_<sigla>.png.
"""
import json, re, sys, os, subprocess, tempfile
from PIL import Image

mods, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
d = json.load(open(os.path.join(mods, 'Workshop', '1631832384.json')))


def fn(url):
    ext = '.png' if url.endswith('.png') else '.jpg'
    return os.path.join(mods, 'Images', re.sub(r'[^A-Za-z0-9]', '', url) + ext)


def ocr(im, psm=7, wl=None):
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
        im.save(f.name)
        cmd = ['tesseract', f.name, '-', '--psm', str(psm)]
        if wl:
            cmd += ['-c', 'tessedit_char_whitelist=' + wl]
        r = subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
    os.unlink(f.name)
    return r


def prep(im):
    g = im.convert('L')
    g = g.point(lambda v: 0 if v < 90 else 255)
    w, h = g.size
    return g.resize((w * 4, h * 4))


# sigle che tesseract non legge
FIX = {'Bx6iwGo.png': 'B', 'ZUHQydB.png': 'B', '4dwoXTN.png': '09', 'oH9njBJ.png': 'B1'}

seen = set()
index = []
for o in d['ObjectStates']:
    if o['Name'] != 'Custom_Tile' or o['Transform']['scaleX'] > 0.5:
        continue
    u = o['CustomImage']['ImageURL']
    b = o['CustomImage'].get('ImageSecondaryURL', '')
    if u in seen:
        continue
    seen.add(u)
    im = Image.open(fn(u)).convert('RGBA')
    r, g, bb, _ = im.getpixel((8, 90))
    if r > 200 and g < 150:
        side = 'o'
    elif g > 180 and r < 180:
        side = 'g'
    else:
        continue  # segnalini neutri: li disegna il gioco
    top = ocr(prep(im.crop((0, 0, 180, 45)))).lower()
    sig = ocr(prep(im.crop((40, 130, 140, 180))), wl='ABCDE0123456789-').upper()
    kind = None
    for k, key in [('unguided', 'ngu'), ('unguided', 'nqu'), ('guided', 'guid'), ('intelligent', 'intel'),
                   ('mims', 'mim'), ('ship', 'ace'), ('ship', 'shi'), ('bc', 'craft')]:
        if key in top:
            kind = k
            break
    if kind is None:
        print('??', u, top, sig)
        continue
    sig = sig.replace(' ', '')
    sig = FIX.get(u.split('/')[-1], sig)
    name = '%s_%s_%s' % (side, kind, sig)
    im.save(os.path.join(out, name + '.png'))
    if b:
        Image.open(fn(b)).convert('RGBA').save(os.path.join(out, name + '_b.png'))
    index.append(name)
index.sort()
json.dump(index, open(os.path.join(out, 'indice.json'), 'w'), indent=0)
print(len(index), index)
