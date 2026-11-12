"""Cuts the raw CC0 recordings (Freesound previews converted to WAV with
`afconvert -f WAVE -d LEI16@44100 -c 1`) into the game's loops and one-shots.

    python3 build_audio.py <raw_dir> <project>/assets/audio

Every source id is a freesound.org sound id; see docs/ASSET_CREDITS.md.
Deterministic (fixed seeds), so the output can be rebuilt exactly.
"""
import sys, os, wave
import numpy as np

RAW, OUT = sys.argv[1], sys.argv[2]
SR = 44100


def load(sid):
    w = wave.open(os.path.join(RAW, "%s.wav" % sid))
    a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    assert w.getframerate() == SR and w.getnchannels() == 1
    return a - a.mean()


def save(path, a, peak=None):
    if peak is not None:
        a = a / (np.abs(a).max() + 1e-9) * peak
    a = np.clip(a, -1.0, 1.0)
    full = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    w = wave.open(full, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((a * 32767.0).astype(np.int16).tobytes())
    w.close()
    print("%-34s %5.2fs peak %.2f rms %.3f" % (path, len(a) / SR, np.abs(a).max(), np.sqrt((a ** 2).mean())))


def seg(a, start, seconds):
    return a[int(start * SR): int((start + seconds) * SR)].copy()


def fade(a, fade_in=0.005, fade_out=0.03):
    a = a.copy()
    n = min(int(fade_in * SR), len(a) // 2)
    m = min(int(fade_out * SR), len(a) // 2)
    if n: a[:n] *= np.linspace(0, 1, n)
    if m: a[-m:] *= np.linspace(1, 0, m) ** 2
    return a


def loopify(a, cross=0.4):
    """Seamless loop: the tail is equal-power crossfaded into the head."""
    n = int(cross * SR)
    body, tail = a[:-n].copy(), a[-n:]
    t = np.linspace(0, np.pi / 2, n)
    body[:n] = body[:n] * np.sin(t) + tail * np.cos(t)
    return body


def rms_to(a, target):
    return a * (target / (np.sqrt((a ** 2).mean()) + 1e-9))


def soft_limit(a, ceiling=0.9):
    return np.tanh(a / ceiling) * ceiling


def lowpass(a, hz):
    k = np.exp(-2 * np.pi * hz / SR)
    out = np.empty_like(a); y = 0.0
    for i in range(len(a)):
        y = (1 - k) * a[i] + k * y
        out[i] = y
    return out


def highpass(a, hz):
    return a - lowpass(a, hz)


def resample(a, ratio):
    """ratio > 1 = higher and shorter."""
    idx = np.arange(0, len(a) - 1, ratio)
    return np.interp(idx, np.arange(len(a)), a)


def steadiest(a, seconds, step=0.25, lo=0.0, hi=None):
    """Start of the window whose loudness varies least (for loops)."""
    hi = len(a) / SR if hi is None else hi
    win = int(0.1 * SR)
    best, best_score = lo, 1e9
    t = lo
    while t + seconds <= hi:
        s = seg(a, t, seconds)
        r = np.sqrt((s[: len(s) // win * win].reshape(-1, win) ** 2).mean(axis=1))
        score = r.std() / (r.mean() + 1e-9)
        if r.mean() > 0.25 * np.sqrt((a ** 2).mean()) and score < best_score:
            best, best_score = t, score
        t += step
    return best


def events(a, min_gap=0.18, count=None, floor=0.2):
    """Onset times of the loudest separate hits (footsteps, knocks)."""
    win = int(0.01 * SR)
    r = np.sqrt((a[: len(a) // win * win].reshape(-1, win) ** 2).mean(axis=1))
    thresh = r.max() * floor
    hits = []
    i = 1
    while i < len(r) - 1:
        if r[i] > thresh and r[i] >= r[i - 1] and r[i] > r[max(i - 3, 0)] * 1.6:
            j = i + int(np.argmax(r[i: i + int(min_gap / 0.01)]))
            hits.append((r[j], i * 0.01))
            i += int(min_gap / 0.01)
        else:
            i += 1
    hits.sort(reverse=True)
    if count: hits = hits[:count]
    return sorted(t for _, t in hits)


def cut_event(a, t, seconds, pre=0.012):
    return fade(seg(a, max(t - pre, 0.0), seconds), 0.004, seconds * 0.5)


def granular(grains, seconds, density, seed, jitter_gain=0.4):
    """Dense texture from short grains (mud slop, snow crunch)."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    out = np.zeros(n + max(len(g) for g in grains))
    for _ in range(int(seconds * density)):
        g = grains[rng.integers(len(grains))]
        g = resample(g, rng.uniform(0.8, 1.25)) * rng.uniform(1 - jitter_gain, 1.0)
        at = rng.integers(n)
        out[at: at + len(g)] += g
    out[: len(out) - n] += out[n:]          # wrap the overhang: seamless
    return out[:n]


# --- Engine: four real small engines, level-matched, as RPM layers ------------
def engine_layer(sid, name, seconds, lo, hi, hp=45.0):
    a = load(sid)
    start = steadiest(a, seconds + 0.5, lo=lo, hi=hi)
    s = highpass(seg(a, start, seconds + 0.5), hp)
    s = soft_limit(rms_to(loopify(s, 0.5), 0.16), 0.85)
    save("engine/%s.wav" % name, s)
    print("   from %.2fs of %s" % (start, sid))

engine_layer(510231, "engine_idle", 4.0, 2.0, 24.0)    # Yamaha Tenere 250 single, idle
engine_layer(379915, "engine_low", 4.0, 3.0, 19.0)     # quad bike / ATV
engine_layer(566047, "engine_mid", 4.0, 14.0, 46.0)    # petrol lawn mower at working speed
engine_layer(680119, "engine_high", 4.5, 0.0, 5.4)     # small generator / mower flat out

# Throttle blip (acceleration response) and lift-off burble from scooter revs.
rev = load(140384)
ev = events(rev, 0.8, 6, 0.45)
print("   scooter rev onsets:", ["%.1f" % t for t in ev])
if ev:
    save("engine/engine_blip.wav", fade(seg(rev, max(ev[len(ev) // 2] - 0.05, 0), 0.9), 0.02, 0.5), 0.7)
quiet = steadiest(rev, 2.5, lo=40.0, hi=58.0)
save("engine/engine_overrun.wav", soft_limit(rms_to(loopify(highpass(seg(rev, quiet, 3.0), 60.0), 0.5), 0.12), 0.8))

# --- Tyres and surfaces ---------------------------------------------------------
grav = load(524115)
t = steadiest(grav, 5.0, lo=5.0, hi=95.0)
save("vehicles/roll_dirt.wav", soft_limit(rms_to(loopify(highpass(seg(grav, t, 5.0), 120.0), 0.5), 0.13), 0.85))
roll = load(390798)
save("vehicles/roll_rattle.wav", soft_limit(rms_to(loopify(seg(roll, 0.5, 4.2), 0.4), 0.12), 0.85))
wood = load(243762)
t = steadiest(wood, 4.5, lo=2.0, hi=20.0)
save("vehicles/roll_wood.wav", soft_limit(rms_to(loopify(seg(wood, t, 4.5), 0.5), 0.15), 0.85))
snow = load(611277)
t = steadiest(snow, 5.0, lo=0.0, hi=40.0)
save("vehicles/roll_snow.wav", soft_limit(rms_to(loopify(highpass(seg(snow, t, 5.0), 150.0), 0.6), 0.12), 0.85))
ice = load(570990)
t = steadiest(ice, 4.0, lo=60.0, hi=110.0)
save("vehicles/roll_ice.wav", soft_limit(rms_to(loopify(highpass(seg(ice, t, 4.0), 400.0), 0.5), 0.1), 0.85))
squelch = load(207142)
grains = [cut_event(squelch, t, 0.35) for t in events(squelch, 0.3, 10, 0.08)]
grains += [cut_event(load(447928), 0.0, 0.3), cut_event(load(447928), 0.42, 0.25)]
save("vehicles/roll_mud.wav", soft_limit(rms_to(granular(grains, 4.0, 9.0, 3), 0.12), 0.85))
drift = load(811620)
skid = load(637161)
grains = [fade(seg(drift, s, 0.22), 0.05, 0.1) for s in np.arange(0.05, 1.0, 0.11)] + \
         [fade(seg(skid, s, 0.2), 0.05, 0.1) for s in np.arange(0.25, 0.8, 0.1)]
save("vehicles/skid_loop.wav", soft_limit(rms_to(granular(grains, 3.0, 26.0, 5, 0.25), 0.13), 0.85))
save("vehicles/brake_skid.wav", fade(seg(skid, 0.12, 0.95), 0.02, 0.4), 0.7)
wind = load(454072)
t = steadiest(wind, 6.0, lo=10.0, hi=160.0)
save("environment/wind_loop.wav", soft_limit(rms_to(loopify(highpass(seg(wind, t, 6.0), 90.0), 1.0), 0.12), 0.85))

# --- Impacts ----------------------------------------------------------------------
thud = load(616295)
save("vehicles/landing.wav", fade(seg(thud, 0.02, 0.5), 0.003, 0.3), 0.85)
smack = load(680108)
save("vehicles/hit_soft.wav", fade(seg(smack, 0.02, 0.28), 0.003, 0.15), 0.7)
blocks = load(521010)
ev = events(blocks, 0.25, 4, 0.3)
for k, t in enumerate(ev[:2]):
    save("vehicles/hit_wood_%d.wav" % (k + 1), cut_event(blocks, t, 0.45), 0.8)
crash = load(321294)
hard = seg(crash, 0.55, 1.2)
hard[: len(seg(thud, 0.02, 0.5))] += seg(thud, 0.02, 0.5) * 0.8
save("vehicles/hit_hard.wav", fade(hard, 0.003, 0.5), 0.9)
splash = load(841538)
save("vehicles/mud_splash.wav", fade(seg(splash, 0.0, 0.8), 0.003, 0.4), 0.8)

# --- Rider ------------------------------------------------------------------------
save("character/yelp_1.wav", fade(seg(load(751702), 0.05, 1.0), 0.01, 0.3), 0.75)
save("character/yelp_2.wav", fade(seg(load(323438), 0.1, 0.8), 0.01, 0.2), 0.75)
save("character/oof.wav", fade(load(719053), 0.005, 0.1), 0.7)
save("character/ouch.wav", fade(load(743350), 0.005, 0.1), 0.7)
body = load(504626)
save("character/body_fall.wav", fade(seg(body, 0.3, 0.9), 0.005, 0.4), 0.85)
save("character/dizzy.wav", fade(load(403002), 0.01, 0.1), 0.7)
save("character/woohoo.wav", fade(load(468898), 0.01, 0.2), 0.7)
save("character/cheer.wav", fade(load(801291), 0.01, 0.15), 0.7)
save("character/mount.wav", fade(load(541507), 0.003, 0.05), 0.7)
gravel_run = load(584321)
for k, t in enumerate(events(gravel_run, 0.22, 5, 0.3)[:4]):
    save("character/step_dirt_%d.wav" % (k + 1), cut_event(gravel_run, t, 0.22), 0.6)
snow_run = load(773740)
for k, t in enumerate(events(snow_run, 0.25, 5, 0.3)[:4]):
    save("character/step_snow_%d.wav" % (k + 1), cut_event(snow_run, t, 0.28), 0.6)

# --- Items ------------------------------------------------------------------------
pop = load(757257)
cork = load(622150)
pickup = np.zeros(int(0.5 * SR))
p1 = fade(seg(pop, 0.03, 0.2), 0.002, 0.1); p2 = fade(resample(seg(cork, 0.12, 0.2), 1.35), 0.002, 0.1)
pickup[: len(p1)] += p1 / np.abs(p1).max()
pickup[int(0.09 * SR): int(0.09 * SR) + len(p2)] += p2 / np.abs(p2).max() * 0.8
save("items/item_pickup.wav", pickup, 0.75)
save("items/item_throw.wav", fade(seg(load(347550), 0.0, 0.45), 0.003, 0.25), 0.75)
splat = np.concatenate([seg(splash, 0.0, 0.7), np.zeros(int(0.2 * SR))])
boots = load(447928)
splat[: len(boots)] += boots * 0.6
save("items/mud_bomb_splat.wav", fade(lowpass(splat, 5000.0), 0.003, 0.4), 0.85)
boing = load(537060)
save("items/spring_punch.wav", fade(seg(boing, 0.02, 0.75), 0.003, 0.3), 0.85)
spring = load(109435)
ev = events(spring, 0.5, 3, 0.4)
if ev:
    save("items/spring_bounce.wav", cut_event(spring, ev[0], 0.7), 0.75)
save("items/banana_slip.wav", fade(seg(load(711794), 0.0, 1.5), 0.01, 0.3), 0.75)
# Turbo: a swoosh into a rising small-engine scream (generator recording swept up).
gen = load(680119)
rise = seg(gen, 0.5, 2.4)
ratio = np.linspace(0.75, 1.5, len(rise))
idx = np.cumsum(ratio); idx = idx[idx < len(gen) - 1]
turbo = np.interp(idx, np.arange(len(gen)), gen)[: int(1.1 * SR)]
turbo *= np.linspace(0.3, 1.0, len(turbo))
sw = load(347550)[: int(0.5 * SR)]
turbo[: len(sw)] += sw / np.abs(sw).max() * 0.6
save("items/turbo_boost.wav", fade(turbo, 0.01, 0.35), 0.85)
save("items/item_denied.wav", fade(resample(seg(smack, 0.02, 0.25), 0.7), 0.003, 0.15), 0.5)
