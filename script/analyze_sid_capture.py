#!/usr/bin/env python3
"""Check bounded Release sound-check captures, not arbitrary music or SID fidelity.

Uses only Python's standard library. Reads the WAV pair beside each version-2
AudioPlaybackValidation report. Nothing is written and any failed gate exits 1.
"""

import argparse
from array import array
import json
import math
from pathlib import Path
import sys
import wave


LEAD = [72, 76, 79, 74, 77, 81, 79, 76, 69, 72, 76, 74, 71, 74, 79, 72]


def read_pcm(path, sample_rate):
    with wave.open(str(path), "rb") as wav:
        if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, sample_rate):
            raise ValueError("expected mono PCM16 at the reported sample rate")
        if not 0 < wav.getnframes() <= sample_rate * 12:
            raise ValueError("capture must contain 0-12 seconds of audio")
        samples = array("h", wav.readframes(wav.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()
    return [value / 32768 for value in samples]


def rms(samples):
    return math.sqrt(sum(value * value for value in samples) / max(1, len(samples)))


def tone_pitch(samples, sample_rate):
    stable = samples[-2 * sample_rate:]
    mean = sum(stable) / len(stable)
    crossings = []
    for i in range(1, len(stable)):
        if stable[i - 1] < mean <= stable[i]:
            crossings.append(i - 1 + (mean - stable[i - 1]) / (stable[i] - stable[i - 1]))
    if len(crossings) < 3:
        return 0.0
    return (len(crossings) - 1) * sample_rate / (crossings[-1] - crossings[0])


def lead_note(samples, sample_rate, time):
    start = round(time * sample_rate)
    count = round(0.060 * sample_rate)
    window = samples[start:start + count]
    if len(window) != count or rms(window) < 0.01:
        return None
    weighted = [value * (0.5 - 0.5 * math.cos(2 * math.pi * i / (count - 1)))
                for i, value in enumerate(window)]
    powers = {}
    for note in range(69, 82):
        frequency = 440 * 2 ** ((note - 69) / 12)
        coefficient = 2 * math.cos(2 * math.pi * frequency / sample_rate)
        q1 = q2 = 0.0
        for value in weighted:
            q0 = value + coefficient * q1 - q2
            q2, q1 = q1, q0
        powers[note] = q1 * q1 + q2 * q2 - coefficient * q1 * q2
    return max(powers, key=powers.get)


def music_proof(head, tail, sample_rate, frame_rate):
    onset = next((i / sample_rate for i, value in enumerate(head) if abs(value) > 0.01), 0)
    period = 12 / frame_rate
    opening = [lead_note(head, sample_rate, onset + 0.080 + i * period) for i in range(16)]
    # The tail can begin anywhere in the tune. Fit only phase/sequence position,
    # never pitch or tempo, then require a full 16-note cycle at the known tempo.
    best = {"matches": 0, "notes": []}
    for phase in range(8):
        offset = 0.030 + phase * period / 8
        notes = [lead_note(tail, sample_rate, offset + i * period) for i in range(16)]
        for rotation in range(16):
            matches = sum(note == LEAD[(i + rotation) % 16] for i, note in enumerate(notes))
            if matches > best["matches"]:
                best = {"matches": matches, "notes": notes, "rotation": rotation}
        if best["matches"] == 16:
            break
    return {"openingNotes": opening, "openingMatches": sum(a == b for a, b in zip(opening, LEAD)),
            "tail": best}


def analyze(path, min_seconds):
    report = json.loads(path.read_text())
    if report.get("version") != 2:
        raise ValueError("requires a fresh version-2 playback report")
    rate = int(report["sampleRate"])
    if rate != 44100:
        raise ValueError("unexpected SID output sample rate")
    head = read_pcm(path.with_suffix(".wav"), rate)
    tail = read_pcm(path.with_name(path.stem + "-tail.wav"), rate)
    failures = []
    playback = report.get("playback") or {}
    for key in ["underrunFrames", "underrunEvents", "overrunFrames", "clippedFrames"]:
        if playback.get(key) != 0:
            failures.append(f"{key}={playback.get(key)}")
    if report.get("invalidSamples") != 0:
        failures.append("invalid samples")
    audio_seconds = report["audioSeconds"]
    if audio_seconds < max(min_seconds, report["requestedSeconds"] - 1):
        failures.append("playback shorter than requested gate")
    if abs(audio_seconds - report["callbackWallSeconds"]) > max(0.1, report["callbackWallSeconds"] * 0.02):
        failures.append("audio/wall-clock duration mismatch")
    if playback.get("sourceFrames", 0) / rate < max(1, min_seconds - 3, report["requestedSeconds"] - 4):
        failures.append("insufficient real source audio")
    accounted = sum(playback.get(key, 0) for key in ["sourceFrames", "startupFrames", "underrunFrames"])
    if accounted != playback.get("renderedFrames"):
        failures.append("source/startup/underrun frame accounting mismatch")
    if abs(playback.get("renderedFrames", 0) / rate - audio_seconds) > 1 / rate:
        failures.append("rendered frame accounting mismatch")
    if abs(len(head) / rate - report["capturedSeconds"]) > 1 / rate:
        failures.append("head capture duration mismatch")
    if abs(len(tail) / rate - report["tailCapturedSeconds"]) > 1 / rate:
        failures.append("tail capture duration mismatch")
    if abs(report["tailStartSeconds"] + len(tail) / rate - audio_seconds) > 1 / rate:
        failures.append("tail does not end at playback completion")
    if report["longestPostOnsetSilenceSeconds"] > 0.5:
        failures.append("long silence after initial sound")
    if rms(head) < 0.02 or rms(tail) < 0.02:
        failures.append("silent/too quiet capture")
    result = {"name": report["name"], "audioSeconds": audio_seconds,
              "headRMS": rms(head), "tailRMS": rms(tail), "playback": playback}
    if report["kind"] == "tone":
        measured = tone_pitch(head, rate)
        tail_measured = tone_pitch(tail, rate)
        requested = report["toneFrequency"]
        result.update(toneHz=measured, tailToneHz=tail_measured, requestedHz=requested)
        if any(abs(value - requested) > max(0.5, requested * 0.002) for value in [measured, tail_measured]):
            failures.append("tone pitch mismatch")
    elif report["kind"] == "music":
        proof = music_proof(head, tail, rate, report["frameRate"])
        result["melody"] = proof
        if proof["openingMatches"] != 16 or proof["tail"]["matches"] != 16:
            failures.append("fixture melody mismatch")
    else:
        failures.append("unknown fixture kind")
    result.update(passed=not failures, failures=failures)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path, nargs="+")
    parser.add_argument("--min-seconds", type=float, default=3)
    args = parser.parse_args()
    passed = True
    for path in args.reports:
        try:
            result = analyze(path, args.min_seconds)
        except (OSError, ValueError, KeyError, TypeError, wave.Error) as error:
            result = {"report": str(path), "passed": False, "failures": [str(error)]}
        print(json.dumps(result, sort_keys=True))
        passed = passed and result["passed"]
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
