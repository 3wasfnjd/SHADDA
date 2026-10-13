"""Original deterministic music loops for SHARARA, CC0. Pure synthesis, no samples.
menu   : calm 96 bpm pads + plucks
battle : 124 bpm kick/hat/bass/arp
boss   : 136 bpm, darker minor bass, double hats, stabs
"""
import math, pathlib, random, struct, wave

out = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
out.mkdir(parents=True, exist_ok=True)
RATE = 22050


def note(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def render(name, bpm, bars, chords, arp_pattern, drums, bass_oct, seed, pad=0.0, stab=False):
    rnd = random.Random(seed)
    beat = 60.0 / bpm
    total = int(RATE * beat * 4 * bars)
    buf = [0.0] * total

    def add(start, length, fn):
        a = int(start * RATE)
        n = int(length * RATE)
        for i in range(n):
            j = a + i
            if j >= total:
                j -= total  # wrap so the loop is seamless
            buf[j] += fn(i / RATE, i / max(1, n))

    for bar in range(bars):
        root = chords[bar % len(chords)]
        triad = [root, root + (3 if root % 2 else 4), root + 7]
        t0 = bar * 4 * beat
        if drums:
            for b in range(4):
                tb = t0 + b * beat
                add(tb, 0.25, lambda t, u: math.sin(math.tau * (50 + 90 * math.exp(-t * 30)) * t) * 0.55 * math.exp(-t * 14))
                if b % 2 == 1:
                    add(tb, 0.18, lambda t, u: rnd.uniform(-1, 1) * 0.22 * math.exp(-t * 22))
                hats = 4 if stab else 2
                for h in range(hats):
                    add(tb + h * beat / hats + (beat / 4 if hats == 2 else 0), 0.04,
                        lambda t, u: rnd.uniform(-1, 1) * 0.07 * (1 - u))
        # bass
        bf = note(root + 12 * bass_oct)
        steps = 8 if drums else 2
        for s in range(steps):
            length = 4 * beat / steps
            add(t0 + s * length, length * 0.9,
                lambda t, u, f=bf: (math.sin(math.tau * f * t) + 0.35 * math.sin(math.tau * 2 * f * t)) * 0.2 * (1 - u) ** 0.6)
        # arpeggio plucks
        step = 4 * beat / len(arp_pattern)
        for k, idx in enumerate(arp_pattern):
            if idx < 0:
                continue
            f = note(triad[idx % 3] + 12 * (1 + idx // 3) + 12)
            add(t0 + k * step, step * 1.6,
                lambda t, u, f=f: (math.sin(math.tau * f * t) * 0.5 + math.sin(math.tau * f * 2.01 * t) * 0.15) * 0.16 * math.exp(-t * 7))
        if pad > 0:
            for n_ in triad:
                f = note(n_ + 12)
                add(t0, 4 * beat, lambda t, u, f=f: math.sin(math.tau * f * t + 0.3 * math.sin(math.tau * 0.5 * t)) * pad * math.sin(math.pi * u) ** 0.8)
        if stab and bar % 2 == 1:
            for n_ in triad:
                f = note(n_ + 24)
                add(t0 + 3.5 * beat, 0.3, lambda t, u, f=f: (2 * ((f * t) % 1) - 1) * 0.06 * (1 - u))

    peak = max(1e-6, max(abs(x) for x in buf))
    gain = 0.8 / peak
    frames = b''.join(struct.pack('<h', int(32767 * max(-1, min(1, x * gain)))) for x in buf)
    with wave.open(str(out / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(frames)
    print(name, round(total / RATE, 2), 's')


render('music_menu', 96, 4, [57, 53, 60, 55], [0, -1, 1, -1, 2, -1, 1, -1], False, -1, 'menu', pad=0.06)
render('music_battle', 124, 8, [57, 57, 53, 55, 57, 57, 60, 55], [0, 1, 2, 3, 2, 1, 0, 2], True, -1, 'battle')
render('music_boss', 136, 8, [50, 50, 53, 49, 50, 50, 46, 49], [0, 2, 3, 2, 4, 2, 3, 1, 0, 2, 3, 2, 4, 5, 3, 2], True, -2, 'boss', stab=True)
