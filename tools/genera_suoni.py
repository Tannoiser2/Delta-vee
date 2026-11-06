#!/usr/bin/env python3
"""Genera gli effetti sonori di DeltaVee (sintetizzati, nessun campione esterno).

Suoni «da fantascienza anni '80»: dardi laser, plasma delle particelle, missili, esplosioni,
impatti, salto nell'iperspazio, scia dei motori e clic dell'interfaccia.
Uso: python3 tools/genera_suoni.py  (scrive assets/audio/*.wav)
"""
import os, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
rng = np.random.default_rng(1981)


def t_(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=None, curve=3.0):
    """inviluppo: attacco breve e decadimento esponenziale"""
    x = np.linspace(0, 1, n)
    e = np.exp(-curve * x)
    na = max(1, int(a * SR))
    e[:na] *= np.linspace(0, 1, na)
    return e


def chirp(f0, f1, d, shape="saw"):
    t = t_(d)
    f = np.geomspace(f0, f1, len(t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "sq":
        return np.sign(np.sin(ph)) * 0.6 + np.sin(ph) * 0.4
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    return np.sin(ph)


def lowpass(x, k):
    """filtro passa-basso a un polo (k fra 0 e 1, più piccolo = più cupo)"""
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(base, x, at):
    i = int(at * SR)
    need = i + len(x)
    if need > len(base):
        base = np.concatenate([base, np.zeros(need - len(base))])
    base[i: i + len(x)] += x
    return base


def save(name, x, vol=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    pcm = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


os.makedirs(OUT, exist_ok=True)

# raffica laser: un dardo che scende di tono
def zap(d=0.2, f0=1900, f1=320):
    s = chirp(f0, f1, d, "sq") * 0.7 + chirp(f0 * 1.5, f1 * 1.5, d, "sin") * 0.3
    return lowpass(s, 0.5) * env(len(s), 0.002, curve=5)

save("laser", zap())
# sbarramento laser: cinque dardi in fila, toni leggermente diversi
b = np.zeros(1)
for i in range(5):
    b = place(b, zap(0.16, 2100 - i * 120, 380 + i * 30) * (1 - i * 0.08), i * 0.075)
save("laser_sbarramento", b)

# raffica di particelle: ronzio di plasma che sale, con crepitii
def plasma(d=0.55, f=110, big=False):
    t = t_(d)
    tone = np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 2.6, len(t))) / SR)
    tone += 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(np.linspace(f * 2, f * 5, len(t))) / SR))
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 28 * t)
    crack = rng.standard_normal(len(t)) * (rng.random(len(t)) > (0.985 if not big else 0.97))
    s = lowpass(tone * trem, 0.35) + lowpass(crack, 0.7) * 1.5
    e = np.minimum(1, t / 0.08) * np.exp(-2.2 * t / d)
    return s * e

save("particelle", plasma())
save("particelle_sbarramento", mix(plasma(0.75, 90, True), plasma(0.75, 135, True) * 0.7, np.concatenate([np.zeros(int(0.08 * SR)), plasma(0.6, 180, True) * 0.5])))

# lancio di un missile: soffio che sale
t = t_(0.8)
n = rng.standard_normal(len(t))
whoosh = lowpass(n, 0.08) * 3 + lowpass(n, 0.3) * np.linspace(0.2, 1, len(t))
whoosh *= np.minimum(1, t / 0.05) * np.exp(-3 * t)
save("missile", mix(whoosh, chirp(180, 520, 0.8, "sin") * 0.25 * np.exp(-3 * t)))

# esplosione: lampo, boato cupo e coda
t = t_(1.6)
n = rng.standard_normal(len(t))
boom = lowpass(n, 0.05) * 4 * np.exp(-2.5 * t) + lowpass(n, 0.4) * np.exp(-9 * t)
boom += np.sin(2 * np.pi * np.cumsum(np.geomspace(90, 30, len(t))) / SR) * np.exp(-3 * t) * 0.8
boom[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
save("esplosione", boom, 0.9)

# impatto sullo scafo: colpo metallico
t = t_(0.35)
clank = sum(np.sin(2 * np.pi * f * t) * np.exp(-k * t) for f, k in [(420, 18), (1130, 25), (2310, 35), (3520, 40)])
clank += lowpass(rng.standard_normal(len(t)), 0.5) * np.exp(-40 * t) * 2
save("impatto", clank, 0.7)

# colpo mancato: dardo che sfuma lontano
save("mancato", lowpass(chirp(900, 2400, 0.25, "sin"), 0.4) * env(int(0.25 * SR), 0.01, curve=6), 0.35)

# salto nell'iperspazio: risucchio che sale e scoppia
t = t_(1.1)
warp = chirp(80, 2600, 1.1, "saw") * np.linspace(0.1, 1, len(t)) ** 2
warp = lowpass(warp, 0.25)
warp = place(warp, lowpass(rng.standard_normal(int(0.3 * SR)), 0.6) * np.exp(-12 * t_(0.3)), 0.95)
save("salto", warp)

# movimento: leggero soffio dei motori
t = t_(0.7)
eng = lowpass(rng.standard_normal(len(t)), 0.04) * 4
eng *= np.sin(np.pi * t / 0.7) ** 2
save("motori", eng, 0.35)

# intercettazione riuscita: allarme breve
t = t_(0.3)
save("intercetta", np.sign(np.sin(2 * np.pi * 880 * t)) * (np.sin(2 * np.pi * 12 * t) > 0) * np.exp(-5 * t) * 0.5, 0.45)

# clic dell'interfaccia
t = t_(0.04)
save("clic", np.sin(2 * np.pi * 1800 * t) * np.exp(-90 * t), 0.35)
print("suoni scritti in", OUT, sorted(os.listdir(OUT)))
