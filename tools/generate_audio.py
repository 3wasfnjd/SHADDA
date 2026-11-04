"""Original deterministic sound cues for SAQR, CC0. Pure synthesis: no recordings,
no third-party sounds. Run: python3 tools/generate_audio.py"""
import math, pathlib, random, struct, wave

out = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
out.mkdir(parents=True, exist_ok=True)
RATE = 24000


def write(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = min(1.0, 0.9 / peak)
    with wave.open(str(out / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(b''.join(struct.pack('<h', int(32767 * max(-1, min(1, s * gain)))) for s in samples))


def render(name, seconds, fn, seed=None):
    rnd = random.Random(seed or name)
    n = int(RATE * seconds)
    write(name, [fn(i / RATE, i / n, rnd) for i in range(n)])


def env(t, u, attack=0.004, power=1.6):
    return min(1.0, t / attack) * max(0.0, 1.0 - u) ** power


class Noise:
    """Low-passed noise so booms rumble instead of hiss."""
    def __init__(self, cutoff):
        self.a = min(1.0, 2 * math.pi * cutoff / RATE)
        self.y = 0.0

    def __call__(self, rnd):
        self.y += self.a * (rnd.uniform(-1, 1) - self.y)
        return self.y


lp_small, lp_big, lp_flak, lp_drop = Noise(1400), Noise(420), Noise(2200), Noise(900)
lp_missile, lp_emissile = Noise(2600), Noise(1800)

render('cannon', 0.07, lambda t, u, r: (r.uniform(-1, 1) * 0.5 + math.sin(math.tau * 180 * t) * 0.6) * env(t, u, 0.001, 2.2))
render('missile', 0.7, lambda t, u, r: (lp_missile(r) * 1.6 + math.sin(math.tau * (300 + 500 * u) * t) * 0.15) * env(t, u, 0.02, 1.2))
render('lock', 0.09, lambda t, u, r: math.sin(math.tau * 1760 * t) * 0.5 * env(t, u, 0.002, 0.8))
render('bomb_drop', 0.5, lambda t, u, r: (math.sin(math.tau * (900 - 600 * u) * t) * 0.3 + lp_drop(r) * 0.4) * env(t, u, 0.005, 1.0))
render('flare', 0.45, lambda t, u, r: (r.uniform(-1, 1) * 0.35 + math.sin(math.tau * 140 * t) * 0.3) * env(t, u, 0.003, 1.4))
render('overheat', 0.5, lambda t, u, r: (math.sin(math.tau * (520 - 300 * u) * t) * 0.4 + r.uniform(-1, 1) * 0.1) * env(t, u, 0.01, 1.0))
render('hit', 0.06, lambda t, u, r: (math.sin(math.tau * 2400 * t) * 0.3 + r.uniform(-1, 1) * 0.4) * env(t, u, 0.001, 2.0))
render('ricochet', 0.25, lambda t, u, r: math.sin(math.tau * (3200 - 2200 * u) * t) * 0.35 * env(t, u, 0.001, 1.5))
render('boom_small', 0.7, lambda t, u, r: (lp_small(r) * 2.2 + math.sin(math.tau * (90 - 50 * u) * t) * 0.5) * env(t, u, 0.002, 2.0))
render('boom_big', 1.4, lambda t, u, r: (lp_big(r) * 3.0 + math.sin(math.tau * (60 - 35 * u) * t) * 0.7) * env(t, u, 0.003, 1.8))
render('enemy_shot', 0.18, lambda t, u, r: math.sin(math.tau * (700 - 400 * u) * t) * 0.4 * env(t, u, 0.002, 1.2))
render('enemy_missile', 0.8, lambda t, u, r: (lp_emissile(r) * 1.5 + math.sin(math.tau * 220 * t) * 0.15) * env(t, u, 0.03, 1.0))
render('flak', 0.2, lambda t, u, r: (math.sin(math.tau * 110 * t) * 0.6 + r.uniform(-1, 1) * 0.4) * env(t, u, 0.001, 2.5))
render('flak_burst', 0.5, lambda t, u, r: lp_flak(r) * 2.0 * env(t, u, 0.001, 2.2))
render('warning', 0.16, lambda t, u, r: (1 if math.sin(math.tau * 1320 * t) > 0 else -1) * 0.25 * env(t, u, 0.004, 0.4))
render('player_hit', 0.4, lambda t, u, r: (math.sin(math.tau * (240 - 120 * u) * t) * 0.5 + r.uniform(-1, 1) * 0.35) * env(t, u, 0.002, 1.6))
render('hangar_open', 1.2, lambda t, u, r: (math.sin(math.tau * 70 * t * (1 + 0.2 * math.sin(math.tau * 9 * t))) * 0.35 + r.uniform(-1, 1) * 0.08 + (math.sin(math.tau * 880 * t) * 0.12 if (t % 0.4) < 0.18 else 0)) * min(1.0, t / 0.05) * max(0.0, 1 - u) ** 0.6)
render('target_pop', 0.22, lambda t, u, r: (math.sin(math.tau * (300 + 500 * u) * t) * 0.4 + r.uniform(-1, 1) * 0.1) * env(t, u, 0.003, 1.2))
render('target_hit', 0.35, lambda t, u, r: (math.sin(math.tau * 1320 * t) * 0.3 + math.sin(math.tau * 1980 * t) * 0.2) * env(t, u, 0.002, 1.8))
render('wave_clear', 0.9, lambda t, u, r: math.sin(math.tau * [660, 880, 1320][min(2, int(u * 3))] * t) * 0.35 * min(1.0, t / 0.01) * (1 - u) ** 0.5)
render('win', 1.6, lambda t, u, r: sum(math.sin(math.tau * f * t) for f in [523, 659, 784][: 1 + min(2, int(u * 5))]) * 0.18 * min(1.0, t / 0.02) * (1 - u) ** 0.7)
render('loss', 1.4, lambda t, u, r: math.sin(math.tau * (330 - 200 * u) * t) * 0.4 * min(1.0, t / 0.02) * (1 - u) ** 0.8)
render('pickup', 0.35, lambda t, u, r: math.sin(math.tau * (880 + 880 * u) * t) * 0.35 * env(t, u, 0.003, 1.0))
print('Generated original mono 24 kHz cues in', out)
