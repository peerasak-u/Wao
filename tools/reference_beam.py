"""PoodPim's RNN-T beam search with hotword biasing (src/asr.rs, src/hotwords.rs), transcribed line by line on
top of reference_transcribe.py's features and encoder, to check the Swift port token for token.

  python -I tools/reference_beam.py --model-dir .model-cache/int8 --vocabulary FILE clip.wav ...

Prints one JSON line per clip: wav, tokens.
"""
import argparse
import json
import pathlib
import sys

import numpy as np
import soundfile as sf

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from reference_transcribe import Transcriber, features  # noqa: E402

BEAM, BONUS, BLANK_BIAS, SYMBOLS = 6, np.float32(2.0), np.float32(-0.5), 3


def key(s):
    return [c for ch in s if not ch.isspace() and ch != "▁" for c in ch.lower()]


class Hotwords:
    def __init__(self, text):
        self.children, self.end, self.words = [{}], [False], []
        for w in (l.strip() for l in text.split("\n")):
            if not w or w.startswith("#"):
                continue
            node = 0
            for c in key(w):
                if c not in self.children[node]:
                    self.children.append({})
                    self.end.append(False)
                    self.children[node][c] = len(self.children) - 1
                node = self.children[node][c]
            if node:
                self.end[node] = True
                self.words.append(w)

    def walk(self, node, k):
        for c in k:
            node = self.children[node].get(c)
            if node is None:
                return None
        return node

    def advance(self, state, piece):
        node, pending = state
        k = key(piece)
        if not self.words or not k:
            return state, np.float32(0)

        def step(n, p):
            return ((n, np.float32(0)), BONUS) if self.end[n] else ((n, np.float32(p + BONUS)), BONUS)

        n = self.walk(node, k)
        if n is not None:
            return step(n, pending)
        n = self.walk(0, k)
        if n is not None:
            st, d = step(n, np.float32(0))
            return st, np.float32(d - pending)
        return (0, np.float32(0)), np.float32(-pending)


def merge_and_prune(hyps):
    out = []
    for h in sorted(hyps, key=lambda h: -h["score"]):
        m = next((m for m in out if m["tokens"] == h["tokens"]), None)
        if m is not None:
            a, c = max(m["score"], h["score"]), min(m["score"], h["score"])
            m["score"] = np.float32(a + np.log1p(np.exp(np.float32(c - a))))
        elif len(out) < BEAM:
            out.append(h)
    return out


def expand(tr, hw, frame, hyps):
    b = len(hyps)
    logits, _, o1, o2 = tr.decoder.run(None, {
        "encoder_outputs": np.repeat(frame.reshape(1, 1024, 1), b, axis=0).astype(np.float32),
        "targets": np.array([[h["last"]] for h in hyps], dtype=np.int32),
        "target_length": np.ones(b, dtype=np.int32),
        "input_states_1": np.concatenate([h["s1"] for h in hyps], axis=1),
        "input_states_2": np.concatenate([h["s2"] for h in hyps], axis=1),
    })
    logits = logits.reshape(b, -1)
    out = []
    for i, h in enumerate(hyps):
        v = logits[i]
        mx = v.max()
        lse = np.float32(mx + np.log(np.exp(v - mx).sum(dtype=np.float32)))
        out.append((dict(h, score=np.float32(h["score"] + v[tr.blank] - lse)), False))
        top = []
        for k in range(tr.blank):
            if len(top) < BEAM or v[k] > top[-1][1]:
                pos = next((j for j, (_, x) in enumerate(top) if v[k] > x), len(top))
                top.insert(pos, (k, v[k]))
                del top[BEAM:]
        for k, x in top:
            ctx, delta = hw.advance(h["ctx"], tr.tokens[k])
            out.append(({"tokens": h["tokens"] + [k], "last": k, "s1": o1[:, i:i + 1], "s2": o2[:, i:i + 1],
                         "score": np.float32(h["score"] + x - lse - BLANK_BIAS + delta), "ctx": ctx}, True))
    return out


def beam_search(tr, hw, encoded):
    z = np.zeros((2, 1, 640), dtype=np.float32)
    hyps = [{"tokens": [], "last": tr.blank, "s1": z, "s2": z, "score": np.float32(0), "ctx": (0, np.float32(0))}]
    for frame in encoded:
        ended, active = [], hyps
        for step in range(SYMBOLS):
            if not active:
                break
            expanded = expand(tr, hw, frame, active)
            going_on = [h for h, e in expanded if e]
            ended = merge_and_prune(ended + [h for h, e in expanded if not e])
            floor = ended[BEAM - 1]["score"] if len(ended) >= BEAM else -np.inf
            active = merge_and_prune([h for h in going_on if h["score"] > floor])
            if step + 1 == SYMBOLS:
                ended += active
        hyps = merge_and_prune(ended)
    best = None
    for h in hyps:
        if best is None or h["score"] - h["ctx"][1] >= best["score"] - best["ctx"][1]:
            best = h
    return best["tokens"] if best else []


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model-dir", required=True)
    p.add_argument("--vocabulary", required=True)
    p.add_argument("--threads", type=int, default=2)
    p.add_argument("wavs", nargs="+")
    a = p.parse_args()
    tr = Transcriber(a.model_dir, a.threads)
    hw = Hotwords(pathlib.Path(a.vocabulary).read_text(encoding="utf-8"))
    for wav in a.wavs:
        audio, _ = sf.read(wav, dtype="float32")
        mel, valid = features(audio)
        print(json.dumps({"wav": wav, "tokens": beam_search(tr, hw, tr.encode(mel, valid, "th-mix"))}), flush=True)


if __name__ == "__main__":
    main()
