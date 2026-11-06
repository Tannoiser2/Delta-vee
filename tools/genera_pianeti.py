#!/usr/bin/env python3
"""Genera le texture dei pianeti e delle lune (equirettangolari, senza giunture) in assets/planets/.

Il rilievo è una somma di onde sulla sfera (direzioni casuali, frequenze crescenti e ampiezze calanti):
continua ovunque, quindi la texture si avvolge sulla sfera senza cuciture. Ogni pianeta ha la sua tavolozza;
le nuvole sono un secondo strato con trasparenza, che nel gioco gira più veloce del pianeta.
Uso: python3 tools/genera_pianeti.py
"""
import os
import numpy as np
from PIL import Image

W, H = 1024, 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "planets")


def sphere_dirs():
    lon = (np.arange(W) + 0.5) / W * 2 * np.pi
    lat = (0.5 - (np.arange(H) + 0.5) / H) * np.pi
    lon, lat = np.meshgrid(lon, lat)
    x = np.cos(lat) * np.cos(lon)
    y = np.sin(lat)
    z = np.cos(lat) * np.sin(lon)
    return np.stack([x, y, z], -1), lat


def field(seed, octaves=7, base=1.6, waves=24):
    rng = np.random.default_rng(seed)
    d, _ = sphere_dirs()
    f = np.zeros(d.shape[:2])
    amp = 1.0
    freq = base
    for _ in range(octaves):
        for _ in range(waves):
            n = rng.normal(size=3)
            n /= np.linalg.norm(n)
            f += amp * np.sin((d @ n) * freq * np.pi + rng.uniform(0, 2 * np.pi))
        amp *= 0.55
        freq *= 2.0
    f -= f.min()
    return f / f.max()


def ramp(h, stops):
    """stops: [(soglia, (r,g,b)), ...] in ordine; interpolazione lineare."""
    out = np.zeros(h.shape + (3,))
    xs = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(h, xs, [s[1][c] for s in stops])
    return out


def save(name, rgb, alpha=None):
    os.makedirs(OUT, exist_ok=True)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    if alpha is None:
        Image.fromarray(rgb, "RGB").save(os.path.join(OUT, name + ".webp"), quality=88)
    else:
        a = np.clip(alpha, 0, 255).astype(np.uint8)
        Image.fromarray(np.dstack([rgb, a]), "RGBA").save(os.path.join(OUT, name + ".webp"), quality=88)
    print(name)


def planet(name, seed, stops, sea, ice=0.0, bands=0.0):
    _, lat = sphere_dirs()
    h = field(seed)
    if bands > 0:
        # gigante gassoso: bande di latitudine mosse dal rilievo
        h = 0.5 + 0.5 * np.sin(lat * 9 + h * 6) * bands + (h - 0.5) * (1 - bands)
    rgb = ramp(h, stops)
    # dettaglio fine
    det = field(seed + 99, octaves=3, base=24, waves=10)
    rgb *= (0.88 + 0.24 * det)[..., None]
    if ice > 0:
        cap = np.clip((np.abs(lat) - (np.pi / 2 - ice)) / 0.12 + (h - 0.5) * 0.8, 0, 1)
        rgb = rgb * (1 - cap[..., None]) + np.array([235, 242, 250]) * cap[..., None]
    save(name, rgb)
    return h


def clouds(name, seed, cover=0.55, tint=(255, 255, 255)):
    c = field(seed, octaves=6, base=2.5, waves=20)
    _, lat = sphere_dirs()
    a = np.clip((c - cover) / 0.18, 0, 1) ** 1.3
    a *= 0.85
    rgb = np.zeros(c.shape + (3,)) + np.array(tint)
    save(name, rgb, a * 255)


def moon(name, seed, base_col, n_craters=140):
    rng = np.random.default_rng(seed)
    d, lat = sphere_dirs()
    h = field(seed, octaves=6, base=2.0, waves=14)
    shade = 0.75 + 0.35 * h
    for _ in range(n_craters):
        c = rng.normal(size=3)
        c /= np.linalg.norm(c)
        r = rng.uniform(0.03, 0.22) ** 1.4
        ang = np.arccos(np.clip(d @ c, -1, 1))
        k = ang / r
        bowl = np.where(k < 1, -0.25 * (1 - k ** 2), 0)
        rim = np.where((k >= 0.85) & (k < 1.25), 0.14 * (1 - np.abs(k - 1.05) / 0.2), 0)
        shade += bowl + np.clip(rim, 0, None)
    rgb = np.array(base_col)[None, None, :] * np.clip(shade, 0.25, 1.4)[..., None]
    save(name, rgb)


if __name__ == "__main__":
    # Esata: pianeta abitato, oceani e continenti
    planet("terra", 11, [(0.0, (8, 28, 70)), (0.48, (20, 70, 140)), (0.53, (60, 130, 170)), (0.55, (200, 190, 140)),
                         (0.6, (70, 130, 60)), (0.72, (40, 95, 45)), (0.82, (120, 105, 80)), (0.92, (170, 160, 150)), (1.0, (240, 240, 245))],
           sea=0.53, ice=0.3)
    clouds("terra_nuvole", 21, cover=0.52)
    # Zaraznov: deserto rosso con mari bassi
    planet("deserto", 12, [(0.0, (60, 30, 25)), (0.35, (110, 50, 30)), (0.5, (170, 85, 45)), (0.65, (205, 130, 70)),
                           (0.8, (225, 175, 115)), (1.0, (245, 220, 180))], sea=0.0, ice=0.15)
    clouds("deserto_nuvole", 22, cover=0.68, tint=(250, 225, 200))
    # Kerberos: gigante gassoso a bande
    planet("gassoso", 13, [(0.0, (70, 55, 90)), (0.3, (140, 110, 150)), (0.5, (200, 170, 150)), (0.7, (230, 205, 170)),
                           (0.85, (180, 120, 90)), (1.0, (250, 235, 210))], sea=0.0, bands=0.8)
    clouds("gassoso_nuvole", 23, cover=0.75, tint=(255, 240, 225))
    # lune
    moon("luna_grigia", 31, (200, 198, 192))
    moon("luna_ocra", 32, (205, 175, 130), n_craters=90)
