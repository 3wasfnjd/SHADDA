"""Original deterministic music loops for SAQR, CC0. Pure synthesis, no samples.
menu   : jaunty 104 bpm march — snare rolls, oom-pah bass, whistled tune
battle : 138 bpm war march — driving snare, bass, brassy saw stabs, tune
boss   : 150 bpm minor — toms, heavier bass, alarm stabs
"""
import math, pathlib, random, struct, wave

out = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
out.mkdir(parents=True, exist_ok=True)
RATE = 22050


def note(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def saw(p):
    return 2.0 * (p % 1.0) - 1.0


def render(name, bpm, bars, chords, tune, seed, snare=True, toms=False, stab=False, minor=False):
    rnd = random.Random(seed)
    beat = 60.0 / bpm
    total = int(RATE * beat * 4 * bars)
    buf = [0.0] * total

    def add(start, length, fn):
        a = int(start * RATE)
        n = int(length * RATE)
        for i in range(n):
            j = (a + i) % total
            buf[j] += fn(i / RATE, i / max(1, n))

    for bar in range(bars):
        root = chords[bar % len(chords)]
        third = 3 if minor else 4
        t0 = bar * 4 * beat
        for b in range(4):
            tb = t0 + b * beat
            add(tb, 0.2, lambda t, u: math.sin(math.tau * (55 + 80 * math.exp(-t * 35)) * t) * 0.6 * math.exp(-t * 12))
            if snare and b % 2 == 1:
                add(tb, 0.18, lambda t, u: (rnd.uniform(-1, 1) * 0.35 + math.sin(math.tau * 190 * t) * 0.15) * math.exp(-t * 20))
            if snare and bar % 2 == 1 and b == 3:
                for k in range(4):
                    add(tb + k * beat / 4, 0.08, lambda t, u: rnd.uniform(-1, 1) * 0.22 * math.exp(-t * 30))
            if toms and b % 2 == 0:
                add(tb + beat / 2, 0.25, lambda t, u: math.sin(math.tau * (120 - 40 * u) * t) * 0.35 * math.exp(-t * 10))
            # Oom-pah: root on the beat, fifth on the off-beat.
            bf = note(root - 24 + (0 if b % 2 == 0 else 7))
            add(tb, beat * 0.45, lambda t, u, f=bf: (math.sin(math.tau * f * t) + 0.4 * saw(f * t)) * 0.22 * (1 - u))
            for h in range(2):
                add(tb + h * beat / 2, 0.03, lambda t, u: rnd.uniform(-1, 1) * 0.06 * (1 - u))
        if stab:
            for k, n_ in enumerate([root, root + third, root + 7]):
                f = note(n_)
                add(t0 + 3.5 * beat, 0.22, lambda t, u, f=f: saw(f * t) * 0.07 * (1 - u))
                add(t0 + 1.5 * beat, 0.16, lambda t, u, f=f: saw(f * t) * 0.06 * (1 - u))
        # Tune: one bar of eighth notes from the pattern (scale degrees).
        scale = [0, 2, 3, 5, 7, 8, 10, 12] if minor else [0, 2, 4, 5, 7, 9, 11, 12]
        pattern = tune[bar % len(tune)]
        step = beat / 2
        for k, deg in enumerate(pattern):
            if deg is None:
                continue
            f = note(root + 12 + scale[deg % 8] + 12 * (deg // 8))
            add(t0 + k * step, step * 0.9, lambda t, u, f=f: (math.sin(math.tau * f * t + 0.4 * math.sin(math.tau * 5 * t)) * 0.6 + saw(f * t) * 0.12) * 0.17 * min(1, t / 0.01) * (1 - u) ** 0.4)

    peak = max(1e-6, max(abs(x) for x in buf))
    g = 0.8 / peak
    with wave.open(str(out / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(b''.join(struct.pack('<h', int(32767 * max(-1, min(1, x * g)))) for x in buf))
    print(name, round(total / RATE, 2), 's')


N = None
render('music_menu', 104, 4, [60, 65, 67, 60],
       [[0, N, 2, 4, 4, N, 2, 0], [3, N, 5, 3, 2, N, 0, N], [4, 4, 5, 4, 2, N, 1, N], [0, 2, 4, 7, 4, N, 0, N]], 'menu', snare=True)
render('music_battle', 138, 8, [57, 57, 53, 55, 57, 57, 60, 64],
       [[0, 0, 2, 4, 4, 2, 4, 7], [7, N, 5, 4, 2, N, 4, N], [0, 2, 4, 5, 7, 5, 4, 2], [4, N, 4, 2, 0, N, N, N]], 'battle', stab=True, minor=True)
render('music_boss', 150, 8, [50, 50, 53, 49, 50, 50, 46, 49],
       [[0, N, 0, 3, N, 4, 3, N], [7, N, 6, 4, 3, N, 1, N], [0, 3, 4, 7, 8, 7, 4, 3], [0, N, N, N, 0, N, N, N]], 'boss', toms=True, stab=True, minor=True)
