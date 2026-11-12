import sys, wave, json, os
import numpy as np
def load(p):
    w = wave.open(p); n = w.getnframes(); sr = w.getframerate()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    return a, sr
cred = json.load(open(os.path.join(sys.argv[1], "credits.json")))
bars = " .:-=+*#%@"
for sid in sys.argv[2:]:
    a, sr = load(os.path.join(sys.argv[1], sid + ".wav"))
    dur = len(a) / sr
    nb = 48
    seg = np.array_split(a, nb)
    rms = np.array([np.sqrt((s ** 2).mean() + 1e-12) for s in seg])
    env = "".join(bars[min(int(r / (rms.max() + 1e-9) * 9.99), 9)] for r in rms)
    # spectral centroid + dominant low freq (30-400 Hz) in 6 windows
    info = []
    for s in np.array_split(a, 6):
        s = s[: min(len(s), sr * 2)]
        sp = np.abs(np.fft.rfft(s * np.hanning(len(s))))
        f = np.fft.rfftfreq(len(s), 1 / sr)
        cen = (sp * f).sum() / (sp.sum() + 1e-9)
        lo = (f > 25) & (f < 400)
        dom = f[lo][np.argmax(sp[lo])]
        info.append("%d/%d" % (dom, cen))
    print("%s %5.1fs peak %.2f rms %.3f |%s| %s  dom/centroid: %s" % (sid, dur, np.abs(a).max(), rms.mean(), env, cred[sid]["title"][:28], " ".join(info)))
