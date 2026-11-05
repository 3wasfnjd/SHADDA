"""Original deterministic sound for SAQR, CC0. Pure synthesis: no recordings,
no third-party sounds. Run: python3 tools/generate_audio.py"""
import math, pathlib, random, struct, wave

out = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
out.mkdir(parents=True, exist_ok=True)
RATE = 22050


def write(name, samples, norm=0.9):
    peak = max(1e-6, max(abs(s) for s in samples))
    g = norm / peak
    with wave.open(str(out / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(b''.join(struct.pack('<h', int(32767 * max(-1, min(1, s * g)))) for s in samples))


def render(name, seconds, fn, norm=0.9):
    rnd = random.Random(name)
    n = int(RATE * seconds)
    write(name, [fn(i / RATE, i / n, rnd) for i in range(n)], norm)


class LP:
    def __init__(self, cutoff):
        self.a = min(1.0, 2 * math.pi * cutoff / RATE)
        self.y = 0.0

    def __call__(self, x):
        self.y += self.a * (x - self.y)
        return self.y


def env(t, u, attack=0.003, power=1.6):
    return min(1.0, t / attack) * max(0.0, 1.0 - u) ** power


def saw(p):
    return 2.0 * (p % 1.0) - 1.0


# --- engine loops: a buzzy propeller drone with blade "chop" (seamless) ---------
def engine_loop(name, base, chop, grit, seconds=1.0):
    rnd = random.Random(name)
    lp = LP(1800)
    n = int(RATE * seconds)
    f = round(base * seconds) / seconds
    c = round(chop * seconds) / seconds
    s = []
    for i in range(n):
        t = i / RATE
        x = saw(f * t) * 0.5 + saw(f * 2 * t + 0.3) * 0.25 + math.sin(math.tau * f * 0.5 * t) * 0.3
        x += rnd.uniform(-1, 1) * grit
        x = lp(x) * (0.7 + 0.3 * (0.5 + 0.5 * math.sin(math.tau * c * t)))
        s.append(x)
    write(name, s, 0.7)


engine_loop('engine', 88, 22, 0.25)
engine_loop('enemy_engine', 72, 18, 0.3)
engine_loop('tank_engine', 40, 8, 0.45)

lp_gun, lp_boom, lp_big, lp_flak, lp_rocket, lp_crash, lp_wh = LP(3200), LP(900), LP(380), LP(1500), LP(2500), LP(1600), LP(1800)
render('gun', 0.07, lambda t, u, r: (r.uniform(-1, 1) * 0.6 + math.sin(math.tau * 140 * t) * 0.8) * env(t, u, 0.0008, 2.6))
render('enemy_gun', 0.09, lambda t, u, r: (r.uniform(-1, 1) * 0.5 + math.sin(math.tau * 110 * t) * 0.7) * env(t, u, 0.0008, 2.4))
render('rocket', 0.8, lambda t, u, r: (lp_rocket(r.uniform(-1, 1)) * 2.0 + math.sin(math.tau * (420 + 700 * u) * t) * 0.12) * env(t, u, 0.01, 1.1))
render('lock', 0.08, lambda t, u, r: math.sin(math.tau * 1660 * t) * env(t, u, 0.002, 0.8))
render('bomb_drop', 0.9, lambda t, u, r: math.sin(math.tau * (1400 - 900 * u) * t) * 0.5 * env(t, u, 0.01, 0.6))
render('whoosh', 0.6, lambda t, u, r: lp_wh(r.uniform(-1, 1)) * 2.5 * math.sin(math.pi * u) ** 1.5)
render('crash', 0.45, lambda t, u, r: (lp_crash(r.uniform(-1, 1)) * 2.0 + math.sin(math.tau * 2200 * t * (1 - 0.5 * u)) * 0.2 * (1 if (t * 30) % 1 < 0.5 else 0)) * env(t, u, 0.001, 1.6))
render('boom_small', 0.8, lambda t, u, r: (lp_boom(r.uniform(-1, 1)) * 2.4 + math.sin(math.tau * (110 - 60 * u) * t) * 0.6) * env(t, u, 0.002, 2.0))
render('boom_big', 1.6, lambda t, u, r: (lp_big(r.uniform(-1, 1)) * 3.2 + math.sin(math.tau * (70 - 40 * u) * t) * 0.8) * env(t, u, 0.003, 1.7))
render('hit', 0.05, lambda t, u, r: (math.sin(math.tau * 2600 * t) * 0.4 + r.uniform(-1, 1) * 0.5) * env(t, u, 0.001, 2.0))
render('ricochet', 0.3, lambda t, u, r: math.sin(math.tau * (3400 - 2400 * u) * t) * 0.5 * env(t, u, 0.001, 1.4))
render('cannon', 0.35, lambda t, u, r: (math.sin(math.tau * (90 - 40 * u) * t) * 0.9 + r.uniform(-1, 1) * 0.5 * max(0, 1 - u * 4)) * env(t, u, 0.001, 2.2))
render('flak_fire', 0.2, lambda t, u, r: (math.sin(math.tau * 160 * t) * 0.7 + r.uniform(-1, 1) * 0.5) * env(t, u, 0.001, 2.8))
render('flak', 0.5, lambda t, u, r: lp_flak(r.uniform(-1, 1)) * 2.4 * env(t, u, 0.001, 2.4))
render('player_hit', 0.3, lambda t, u, r: (math.sin(math.tau * 900 * t) * 0.3 + r.uniform(-1, 1) * 0.5) * env(t, u, 0.001, 1.8))
render('engine_start', 1.4, lambda t, u, r: (saw(t * (20 + 70 * u * u)) * 0.6 + r.uniform(-1, 1) * 0.15 * (1 if (t * (6 + 20 * u)) % 1 < 0.3 else 0)) * min(1, t / 0.05) * (1 - u) ** 0.3)
render('engine_die', 1.6, lambda t, u, r: (saw(t * (90 - 70 * u)) * 0.5 + r.uniform(-1, 1) * 0.2) * min(1, t / 0.02) * (1 - u) ** 1.2)
render('plane_in', 1.8, lambda t, u, r: saw(t * (70 + 25 * math.sin(math.pi * u))) * 0.5 * math.sin(math.pi * u) ** 1.2)
render('tank_in', 1.6, lambda t, u, r: (saw(t * 38) * 0.5 + r.uniform(-1, 1) * 0.25 * (1 if (t * 12) % 1 < 0.4 else 0.3)) * min(1, t / 0.2) * (1 - u) ** 0.5)
render('hatch', 0.25, lambda t, u, r: (math.sin(math.tau * 300 * t) * 0.4 + r.uniform(-1, 1) * 0.3) * env(t, u, 0.002, 1.5))
render('thud', 0.35, lambda t, u, r: (math.sin(math.tau * (90 - 40 * u) * t) * 0.8 + r.uniform(-1, 1) * 0.3 * max(0, 1 - u * 5)) * env(t, u, 0.001, 2.0))
render('inflate', 1.2, lambda t, u, r: r.uniform(-1, 1) * 0.4 * math.sin(math.pi * u) * (0.6 + 0.4 * math.sin(math.tau * 9 * t)))
render('pop', 0.3, lambda t, u, r: (r.uniform(-1, 1) * 0.8 + math.sin(math.tau * 500 * t) * 0.3) * env(t, u, 0.0005, 3.0))
render('siren', 2.2, lambda t, u, r: math.sin(math.tau * (520 + 260 * math.sin(math.tau * 0.9 * t)) * t) * 0.4 * min(1, t / 0.2) * min(1, (2.2 - t) / 0.4))
render('wave_clear', 1.0, lambda t, u, r: (saw(t * [523, 659, 784, 1046][min(3, int(u * 4))]) * 0.3) * min(1.0, t / 0.01) * (1 - u) ** 0.5)
render('win', 2.0, lambda t, u, r: sum(saw(t * f) for f in [392, 523, 659, 784][: 1 + min(3, int(u * 6))]) * 0.15 * min(1.0, t / 0.02) * (1 - u) ** 0.6)
render('loss', 1.6, lambda t, u, r: saw(t * (330 - 200 * u)) * 0.4 * min(1.0, t / 0.02) * (1 - u) ** 0.8)
render('pickup', 0.4, lambda t, u, r: math.sin(math.tau * (660 + 900 * u) * t) * 0.5 * env(t, u, 0.003, 0.9))
render('click', 0.08, lambda t, u, r: math.sin(math.tau * 900 * t) * env(t, u, 0.001, 2.0))
print('Generated cues and engine loops in', out)
