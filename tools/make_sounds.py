#!/usr/bin/env python3
"""glyph's interface sounds -- synthesized, not sampled.

Original soft blips in the spirit of a certain fruit company's restraint:
short, lowpassed, fast decays, nothing above a whisper. Pure stdlib
(wave + math + one seeded PRNG), deterministic -- re-running this script
reproduces the committed WAVs byte for byte.

    python3 tools/make_sounds.py

writes config/quickshell/glyph/assets/sounds/*.wav (44.1 kHz mono 16-bit)
and verifies each one on the way out: format, duration, peak level, and
that no sample ever hits the rail (no clipping plateau).

One file in that directory is NOT made here: swoosh.wav, the workspace-
switch sound, is a sample the user picked himself -- "Copyright Free
Swoosh" by DRAGON-STUDIO on Pixabay (pixabay.com/sound-effects/
film-special-effects-copyright-free-swoosh-487669/), trimmed to its body
and normalised into the set's format by hand. Don't regenerate it.
"""

import math
import os
import random
import struct
import sys
import wave

FS = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "config", "quickshell", "glyph", "assets", "sounds")


def env(t, attack, tau):
    """soft attack (raised cosine) into an exponential decay"""
    a = 1.0 if t >= attack else 0.5 - 0.5 * math.cos(math.pi * t / attack)
    return a * math.exp(-t / tau)


def voice(buf, start, dur, f0, f1, tau, gain, harm, attack=0.004):
    """one sine partial family with an exponential pitch glide f0 -> f1"""
    i0, n = int(start * FS), int(dur * FS)
    phase = 0.0
    for j in range(n):
        t = j / FS
        f = f0 * (f1 / f0) ** (t / dur) if f1 != f0 else f0
        phase += 2 * math.pi * f / FS
        e = env(t, attack, tau) * gain
        s = 0.0
        for k, g in harm.items():
            s += g * math.sin(phase * k)
        if i0 + j < len(buf):
            buf[i0 + j] += e * s


def noise(buf, start, dur, tau, gain, seed=7):
    """a short burst of (seeded, hence deterministic) noise"""
    rnd = random.Random(seed)
    i0, n = int(start * FS), int(dur * FS)
    for j in range(n):
        if i0 + j < len(buf):
            buf[i0 + j] += env(j / FS, 0.0015, tau) * gain * rnd.uniform(-1, 1)


def lowpass(buf, fc):
    """one pole, for warmth: takes the digital edge off"""
    a = 1 - math.exp(-2 * math.pi * fc / FS)
    y = 0.0
    for i, x in enumerate(buf):
        y += a * (x - y)
        buf[i] = y


def finish(buf, peak):
    """fade the last 8 ms to zero (no end click), scale to the peak, quantize"""
    tail = int(0.008 * FS)
    for j in range(tail):
        buf[len(buf) - tail + j] *= 0.5 + 0.5 * math.cos(math.pi * j / tail)
    top = max(abs(x) for x in buf) or 1.0
    return [max(-32767, min(32767, int(x / top * peak * 32767))) for x in buf]


def render(dur):
    return [0.0] * int(dur * FS)


# each sound: (duration s, lowpass Hz, target peak, builder)
def pop():
    b = render(0.075)
    voice(b, 0, 0.075, 720, 330, 0.016, 1.0, {1: 1.0, 2: 0.14}, attack=0.003)
    return b, 6000, 0.50


def tick():
    b = render(0.045)
    voice(b, 0, 0.045, 890, 890, 0.009, 1.0, {1: 1.0, 2: 0.18}, attack=0.0015)
    return b, 7000, 0.45


def lock():
    b = render(0.16)
    voice(b, 0, 0.07, 330, 255, 0.020, 0.9, {1: 1.0, 2: 0.10}, attack=0.003)
    voice(b, 0.055, 0.10, 186, 175, 0.032, 1.0, {1: 1.0, 2: 0.08, 3: 0.03}, attack=0.004)
    return b, 4200, 0.52


def unlock():
    b = render(0.17)
    voice(b, 0, 0.055, 262, 262, 0.018, 0.8, {1: 1.0, 2: 0.10}, attack=0.003)
    voice(b, 0.05, 0.115, 392, 466, 0.036, 0.95, {1: 1.0, 2: 0.12}, attack=0.004)
    return b, 5200, 0.50


def notify():
    b = render(0.30)
    voice(b, 0, 0.30, 1568, 1568, 0.105, 0.50, {1: 1.0}, attack=0.006)
    voice(b, 0, 0.30, 2093, 2093, 0.085, 0.30, {1: 1.0}, attack=0.006)
    voice(b, 0, 0.30, 2637, 2637, 0.060, 0.11, {1: 1.0}, attack=0.006)
    return b, 9000, 0.42


def shot():
    b = render(0.095)
    noise(b, 0, 0.03, 0.007, 0.8)
    voice(b, 0.010, 0.07, 1250, 1180, 0.015, 0.32, {1: 1.0}, attack=0.002)
    return b, 3800, 0.50


def charge():
    b = render(0.21)
    voice(b, 0, 0.09, 659.25, 659.25, 0.038, 0.75, {1: 1.0, 2: 0.08}, attack=0.004)
    voice(b, 0.062, 0.145, 987.77, 987.77, 0.052, 0.80, {1: 1.0, 2: 0.07}, attack=0.004)
    return b, 6000, 0.46


def close():
    # pop's mirror: a lower, duller thock falling away, with the faintest tap
    # of noise at the head -- a window folding shut, not opening
    b = render(0.08)
    noise(b, 0, 0.02, 0.005, 0.22)
    voice(b, 0, 0.08, 340, 148, 0.015, 1.0, {1: 1.0, 2: 0.10}, attack=0.002)
    return b, 4500, 0.48


def briup():
    # the volume tick's brighter sibling, gliding a fourth up as the screen does
    b = render(0.055)
    voice(b, 0, 0.055, 940, 1318, 0.011, 1.0, {1: 1.0, 2: 0.15}, attack=0.0015)
    return b, 7500, 0.44


def bridown():
    b = render(0.055)
    voice(b, 0, 0.055, 1318, 940, 0.011, 1.0, {1: 1.0, 2: 0.15}, attack=0.0015)
    return b, 7500, 0.44


SOUNDS = {"pop": pop, "tick": tick, "lock": lock, "unlock": unlock,
          "notify": notify, "shot": shot, "charge": charge,
          "close": close, "briup": briup, "bridown": bridown}


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    print(f"{'name':8} {'ms':>5} {'peak':>6} {'bytes':>7}")
    for name, make in SOUNDS.items():
        buf, fc, peak = make()
        lowpass(buf, fc)
        samples = finish(buf, peak)
        path = os.path.join(OUT, name + ".wav")
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(FS)
            w.writeframes(struct.pack(f"<{len(samples)}h", *samples))
        # verify by re-opening: format, duration, peak, no clipping plateau
        with wave.open(path, "rb") as w:
            assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == FS, name
            raw = w.readframes(w.getnframes())
        got = struct.unpack(f"<{len(raw) // 2}h", raw)
        ms = len(got) / FS * 1000
        pk = max(abs(x) for x in got) / 32767
        plateau = sum(1 for a, b in zip(got, got[1:]) if abs(a) >= 32767 and a == b)
        assert 100 <= ms <= 400 or ms < 100, name
        assert 0.2 <= pk <= 0.8, (name, pk)
        assert plateau == 0 and max(got) < 32767 and min(got) > -32767, name
        size = os.path.getsize(path)
        total += size
        print(f"{name:8} {ms:5.0f} {pk:6.2f} {size:7}")
    print(f"total {total} bytes -> {os.path.normpath(OUT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
