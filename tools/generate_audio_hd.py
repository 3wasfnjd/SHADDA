"""SAQR v1.5 'HD' sounds: engines, explosions and guns rebuilt at 44.1 kHz with
layered synthesis (numpy). Original, deterministic, CC0 — no recordings.
Overwrites only the files listed here; the rest still come from
generate_audio.py.  Run: python3 tools/generate_audio_hd.py"""
import pathlib
import wave

import numpy as np
from scipy import signal

OUT = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
SR = 44100
rng = np.random.default_rng(1945)


def write(name, x, peak=0.92):
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    m = np.max(np.abs(x)) or 1.0
    x = np.clip(x / m * peak, -1, 1)
    with wave.open(str(OUT / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, SR, 0, 'NONE', 'not compressed'))
        w.writeframes((x * 32767).astype('<i2').tobytes())
    print(name, f'{len(x) / SR:.2f}s')


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def noise(n):
    return rng.uniform(-1, 1, n)


def lp(x, hz, order=2):
    b, a = signal.butter(order, min(hz, SR * 0.45) / (SR / 2), 'low')
    return signal.lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), 'high')
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], 'band')
    return signal.lfilter(b, a, x)


def env(t, attack, decay_tau):
    return np.minimum(1.0, t / max(attack, 1e-5)) * np.exp(-t / decay_tau)


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def seamless(x, fade=0.05):
    """Crossfade the tail into the head so the clip loops without a click."""
    n = int(SR * fade)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    w = np.linspace(0, 1, n)
    return np.concatenate([body, tail * (1 - w) + head * w])


# --- engines ---------------------------------------------------------------
def radial_engine(sec, rpm_hz, cylinders, prop_blades, grit, warmth):
    """Firing pulses of a radial engine (each cylinder slightly different),
    exhaust crackle riding on them, and the propeller's blade-pass buzz."""
    t = t_axis(sec + 0.05)
    n = len(t)
    fire = rpm_hz * cylinders / 2.0          # 4-stroke: each cylinder fires every 2 revs
    # Wander the speed a hair so it breathes.
    wobble = 1.0 + 0.008 * np.sin(2 * np.pi * 0.7 * t) + 0.004 * np.sin(2 * np.pi * 2.3 * t)
    ph = np.cumsum(fire * wobble) / SR
    idx = np.floor(ph).astype(int)
    frac = ph - idx
    # Per-cylinder strength, repeating every `cylinders` pulses.
    strengths = 0.75 + 0.5 * rng.random(cylinders)
    amp = strengths[idx % cylinders]
    pulse = amp * np.exp(-frac * 9.0) * (1 - np.exp(-frac * 120.0))
    # Small headset speakers barely move below ~150 Hz: keep the growl in the mids.
    body = hp(lp(pulse, 1400 * warmth), 140) * 2.2 + lp(pulse, 160) * 0.25
    crackle = bp(noise(n), 700, 4000) * pulse ** 2 * grit * 1.6
    blade = fire * 0 + rpm_hz * prop_blades
    prop = np.sin(2 * np.pi * np.cumsum(blade * wobble) / SR)
    prop = lp(sat(prop * 1.5, 2.0) * 0.1, 1200)
    whoosh = bp(noise(n), 300, 2200) * (0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(blade * wobble) / SR)) * 0.12
    x = sat(body + crackle + prop + whoosh, 1.6)
    return seamless(x)


# --- explosions ------------------------------------------------------------
def explosion(sec, size):
    t = t_axis(sec)
    n = len(t)
    # 1) Crack: very short bright transient.
    crack = hp(noise(n), 1500) * env(t, 0.0005, 0.012) * 0.9
    # 2) Blast body: noise through a falling low-pass, saturated.
    cut = 200 + 5200 * np.exp(-t / (0.08 * size))
    body = np.zeros(n)
    nz = noise(n)
    blk = 512
    zi = None
    for i in range(0, n, blk):
        b, a = signal.butter(2, cut[i] / (SR / 2), 'low')
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0
        seg, zi = signal.lfilter(b, a, nz[i:i + blk], zi=zi)
        body[i:i + blk] = seg
    body = hp(body, 120) * env(t, 0.002, 0.25 * size) * 2.0
    # 3) Thump: a sine dropping 90 → 32 Hz (the bit you feel).
    f = 32 + 58 * np.exp(-t / 0.09)
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.003, 0.22 * size) * 0.7
    # 4) Rolling rumble tail with slow swells.
    swell = 0.6 + 0.4 * lp(noise(n), 3) / (np.max(np.abs(lp(noise(n), 3))) + 1e-9)
    rumble = lp(noise(n), 140) * env(t, 0.05, 0.9 * size) * swell * 0.7
    roar = bp(noise(n), 180, 1400) * env(t, 0.01, 0.45 * size) * swell * 1.7
    # 5) Debris: sparse crackles and pings in the tail.
    debris = np.zeros(n)
    for _ in range(int(14 * size)):
        at = int(SR * rng.uniform(0.08, 0.9 * sec))
        ln = int(SR * rng.uniform(0.004, 0.02))
        if at + ln < n:
            debris[at:at + ln] += hp(noise(ln), 2500) * np.exp(-np.arange(ln) / (ln * 0.3)) * rng.uniform(0.1, 0.35)
    x = crack + body + thump + rumble + roar + debris * env(t, 0.05, 0.6 * size)
    return sat(x, 1.8)


# --- guns ------------------------------------------------------------------
def gunshot(sec, low_hz, snap, body_tau, tail_tau, ring_hz=0):
    t = t_axis(sec)
    n = len(t)
    click = hp(noise(n), 3000) * env(t, 0.0002, 0.003) * snap
    blast = bp(noise(n), 300, 5000) * env(t, 0.0004, body_tau)
    f = low_hz * (1 + 1.5 * np.exp(-t / 0.006))
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.0008, body_tau * 1.6) * 0.5
    tail = lp(noise(n), 1800) * env(t, 0.004, tail_tau) * 0.35
    ring = 0
    if ring_hz:
        ring = np.sin(2 * np.pi * ring_hz * t) * env(t, 0.001, 0.03) * 0.12
    return sat(click + blast + thump + tail + ring, 2.2)


def main():
    write('engine', radial_engine(2.0, rpm_hz=32, cylinders=7, prop_blades=3, grit=0.5, warmth=1.0), 0.8)
    write('enemy_engine', radial_engine(2.0, rpm_hz=27, cylinders=9, prop_blades=3, grit=0.8, warmth=0.8), 0.8)
    write('boom_big', explosion(3.2, 1.6))
    write('boom_small', explosion(1.6, 0.8))
    write('gun', gunshot(0.16, 140, 0.8, 0.012, 0.05, 2400), 0.85)
    write('enemy_gun', gunshot(0.14, 120, 0.6, 0.01, 0.04), 0.8)
    write('cannon', gunshot(0.45, 110, 1.0, 0.03, 0.16), 0.92)
    write('cannon20', gunshot(0.3, 95, 1.0, 0.02, 0.1, 1800), 0.9)
    write('flak', explosion(1.1, 0.55), 0.85)
    write('crash', explosion(2.4, 1.2))


if __name__ == '__main__':
    main()
