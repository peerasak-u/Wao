# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy==2.5.5", "pythainlp==5.4.0"]
# ///
"""Builds thai-typing.bin, the keyboard's Thai character language model and word list, plus its test fixtures.

  uv run tools/build_typing_model.py

Downloads the corpora (pinned to a git commit, checked by sha256) into .model-cache/typing-corpora, splits off the
same 5 % holdout as the research simulation, trains an interpolated Witten-Bell character 6-gram on the rest and
prunes it until the whole file fits in --max-bytes. The word list is PyThaiNLP's words_th, ranked by how often each
word occurs in the training lines (segmented with newmm) and in PyThaiNLP's Thai National Corpus frequencies.

Writes, relative to the repo root:
  Packages/WaoCore/Sources/WaoCore/Resources/thai-typing.bin
  Packages/WaoCore/Tests/WaoCoreTests/Fixtures/typing-holdout-{chat,formal}.txt   lines never trained on
  Packages/WaoCore/Tests/WaoCoreTests/Fixtures/typing-golden.jsonl                ln P from the unquantised model

File format (little-endian; every section starts on an 8-byte boundary):
  header     magic "WAOTYPE1", u32 version, u8 order, u8 symbolCount, u8 maxWordLength, u8 0,
             u32 entryCount, u32 wordCount, then u32 offsets of: symbols, logpCodebook, bowCodebook, keys, logp,
             bow, wordOffsets, wordBlob, wordFreq, buildInfo; u32 buildInfo length
  symbols    symbolCount x u32 Unicode scalar; symbol id = index + 1, so id 0 never names a symbol
  codebooks  256 x f32 each: ln P and ln backoff weight
  keys       entryCount x u64, ascending: a string of 0...order symbol ids, 7 bits each, first symbol highest
  logp, bow  entryCount x u8 codebook index: ln P(last symbol | the ones before) and, for the string as a context,
             the ARPA backoff weight (0 nats when it is never a context)
  words      wordOffsets (wordCount + 1) x u32 into wordBlob, one symbol id byte per character, words sorted by
             those bytes; wordFreq wordCount x u8, larger is more frequent
  buildInfo  UTF-8 JSON naming the sources and the pruning
"""
import argparse
import hashlib
import json
import math
import random
import re
import struct
import sys
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "Packages/WaoCore/Sources/WaoCore/Resources/thai-typing.bin"
FIXTURES = ROOT / "Packages/WaoCore/Tests/WaoCoreTests/Fixtures"

CV_COMMIT = "3acf94e65c97ea1409a070ade72f379e7caea7da"
WS_COMMIT = "c1d063649abc3a6870b5fd1aae26cd1c64bdde7b"
SOURCES = {
    "cv.txt": (
        f"https://raw.githubusercontent.com/common-voice/common-voice/{CV_COMMIT}/server/data/th/sentence-collector.txt",
        "9fbd58d33edd6da3ccf631b21fe6d7a48b1d7c8bfab5b0acdfbac9f0ab7b01ab",
    ),
    **{
        f"wisesight-{name}.txt": (
            f"https://raw.githubusercontent.com/PyThaiNLP/wisesight-sentiment/{WS_COMMIT}/{name}.txt",
            sha,
        )
        for name, sha in (
            ("neg", "a58220b2221cc51e2072e676329b6a2249046ccc2e5692e53636430eaee82690"),
            ("neu", "afe5cb9b3d09cff1ae482826e1aeebba402c602f451dc7d5198a725c1bcd44e3"),
            ("pos", "a118567bfbf9e1aae0fcd621235a4b27319945746907c790cc6957aacab6a0a1"),
            ("q", "446b7f2df273f4ab2037ad31e2576d8c0be6858b2ade9477d90a8fd8e0bb9f8a"),
        )
    },
}

# Typing.kedmanee, both layers. TypingModelTests fails if the two drift apart.
KEDMANEE = [
    ("ๅ / - ภ ถ ุ ึ ค ต จ ข ช", "+ ๑ ๒ ๓ ๔ ู ฿ ๕ ๖ ๗ ๘ ๙"),
    ("ๆ ไ ำ พ ะ ั ี ร น ย บ ล", "๐ \" ฎ ฑ ธ ํ ๊ ณ ฯ ญ ฐ ,"),
    ("ฟ ห ก ด เ ้ ่ า ส ว ง ฃ", "ฤ ฆ ฏ โ ฌ ็ ๋ ษ ศ ซ . ฅ"),
    ("ผ ป แ อ ิ ื ท ม ใ ฝ", "( ) ฉ ฮ ฺ ์ ? ฒ ฬ ฦ"),
]
SYMBOLS = [" "] + sorted({c for row in KEDMANEE for layer in row for c in layer.split(" ")})
ID = {c: i + 1 for i, c in enumerate(SYMBOLS)}
V = len(SYMBOLS)
ORDER = 6
MAX_WORD = 24
HOLDOUT = 0.05
TEST_CHARS = 30000


def fetch(cache):
    cache.mkdir(parents=True, exist_ok=True)
    paths = {}
    for name, (url, sha) in SOURCES.items():
        path = cache / name
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            print(f"downloading {url}", file=sys.stderr)
            data = urllib.request.urlopen(url, timeout=60).read()
            got = hashlib.sha256(data).hexdigest()
            if got != sha:
                sys.exit(f"{name}: sha256 {got}, expected {sha}")
            path.write_bytes(data)
        paths[name] = path
    return paths


def normalize(line):
    """What the keyboard could have typed: anything off the Kedmanee keys becomes one space."""
    return re.sub(r" +", " ", "".join(c if c in ID and c != " " else " " for c in line)).strip()


def split(lines, rng):
    lines = lines[:]
    rng.shuffle(lines)
    n = int(len(lines) * HOLDOUT)
    return lines[n:], lines[:n]


def cap(lines):
    out, n = [], 0
    for line in lines:
        if n >= TEST_CHARS:
            break
        out.append(line)
        n += len(line)
    return out


def load_corpora(paths):
    """The research simulation's split, line for line, so its numbers and the Swift eval's are comparable."""
    ws = []
    for name in ("neg", "neu", "pos", "q"):
        ws += paths[f"wisesight-{name}.txt"].read_text(encoding="utf-8").splitlines()
    cv = [l.strip().strip('"') for l in paths["cv.txt"].read_text(encoding="utf-8").splitlines()]
    rng = random.Random(0)
    ws_train, ws_test = split([n for n in map(normalize, ws) if n], rng)
    cv_train, cv_test = split([n for n in map(normalize, cv) if n], rng)
    return ws_train + cv_train, {"chat": cap(ws_test), "formal": cap(cv_test)}


class Model:
    """Interpolated Witten-Bell, held as ARPA entries so it can be pruned and read with plain backoff."""

    def __init__(self, lines):
        pad = " " * (ORDER - 1)
        count = Counter()
        for line in lines:
            s = pad + line + " "
            for i in range(ORDER - 1, len(s)):
                for n in range(1, ORDER + 1):
                    count[s[i - n + 1 : i + 1]] += 1
        self.count = count
        total = defaultdict(int)
        types = defaultdict(int)
        for s, c in count.items():
            total[s[:-1]] += c
            types[s[:-1]] += 1
        self.total, self.types = dict(total), dict(types)
        self.full = {}
        for s in sorted(set(count) | set(total), key=len):
            if s:
                self.full[s] = self._wb(s)

    def _wb(self, s):
        h, c = s[:-1], s[-1]
        lower = self.full.get(s[1:]) if len(s) > 1 else None
        lower = math.exp(lower) if lower is not None else self._backed(c, h[1:]) if h else 1 / V
        C, T = self.total.get(h, 0), self.types.get(h, 0)
        if not C:
            return math.log(lower)
        return math.log((self.count.get(s, 0) + T * lower) / (C + T))

    def _backed(self, c, h):
        while True:
            if h + c in self.full:
                return math.exp(self.full[h + c])
            C, T = self.total.get(h, 0), self.types.get(h, 0)
            w = T / (C + T) if C else 1.0
            if not h:
                return w / V
            return w * self._backed(c, h[1:])

    def prune(self, min_count):
        """Keeps every string shorter than 3 and every longer one seen min_count times (as a string or a context);
        that set is prefix-closed, so a kept string's context always has an entry. Backoff weights are then
        re-derived so each context's distribution still sums to one."""
        self.min_count = min_count
        self.logp = {s: p for s, p in self.full.items() if len(s) < 3 or max(self.count.get(s, 0), self.total.get(s, 0)) >= min_count}
        children = defaultdict(list)
        for s in self.logp:
            children[s[:-1]].append(s[-1])
        self.bow = {}
        for h in sorted(set(self.logp) | {""}, key=len):
            kept = children.get(h, [])
            if not kept:
                continue
            num = 1 - sum(math.exp(self.logp[h + c]) for c in kept)
            den = 1 - sum(math.exp(self.lookup(c, h[1:])) for c in kept) if h else 1 - len(kept) / V
            self.bow[h] = math.log(num / den) if num > 1e-12 and den > 1e-12 else 0.0

    def lookup(self, c, h):
        """ln P(c | h) in the pruned model: the reader's algorithm, unquantised."""
        h = h[-(ORDER - 1) :] if ORDER > 1 else ""
        acc = 0.0
        while True:
            if h + c in self.logp:
                return acc + self.logp[h + c]
            acc += self.bow.get(h, 0.0)
            if not h:
                return acc + math.log(1 / V)
            h = h[1:]

    def entries(self):
        return sorted(set(self.logp) | set(self.bow), key=key)


def key(s):
    k = 0
    for c in s:
        k = (k << 7) | ID[c]
    return k


def codebook(values, keep_zero=False):
    """Evenly spaced levels over the whole range. k-means spent its levels on the common values and left the tails,
    where several backoff weights add up on one lookup, off by several nats."""
    v = np.asarray(values, dtype=np.float64)
    levels = np.linspace(v.min(), v.max(), 255 if keep_zero else 256)
    return (np.concatenate([[0.0], levels]) if keep_zero else levels).astype(np.float32)


def quantize(values, book, keep_zero=False):
    v = np.asarray(values, dtype=np.float64)
    levels = book[1:] if keep_zero else book
    step = (levels[-1] - levels[0]) / (len(levels) - 1)
    q = np.clip(np.rint((v - levels[0]) / step), 0, len(levels) - 1).astype(np.int64)
    if keep_zero:
        q = np.where(v == 0.0, 0, q + 1)
    return q.astype(np.uint8)


def words(train, tnc_path, words_path, max_words):
    from pythainlp.tokenize import word_tokenize

    candidates = {
        w for w in words_path.read_text(encoding="utf-8").split("\n")
        if 2 <= len(w) <= MAX_WORD and all(c in ID and c != " " for c in w)
    }
    corpus = Counter(t for line in train for t in word_tokenize(line, engine="newmm", keep_whitespace=False))
    tnc = Counter()
    for row in tnc_path.read_text(encoding="utf-8").splitlines():
        w, _, n = row.partition("\t")
        if n:
            tnc[w] += int(n)
    n_corpus, n_tnc = sum(corpus.values()), sum(tnc.values())
    per_million = {w: 5e5 * (corpus[w] / n_corpus + tnc[w] / n_tnc) for w in candidates}
    ranked = sorted((w for w, f in per_million.items() if f > 0), key=lambda w: (-per_million[w], w))[:max_words]
    top = math.log1p(per_million[ranked[0]])
    freq = {w: max(1, round(255 * math.log1p(per_million[w]) / top)) for w in ranked}
    return sorted(ranked, key=lambda w: bytes(ID[c] for c in w)), freq


def align(buf):
    buf.extend(b"\0" * (-len(buf) % 8))


def serialize(model, word_list, freq, info):
    entries = model.entries()
    logp = [model.logp.get(s, 0.0) for s in entries]
    bow = [model.bow.get(s, 0.0) for s in entries]
    logp_book = codebook([p for s, p in zip(entries, logp) if s])
    bow_book = codebook([b for b in bow if b != 0.0], keep_zero=True)
    blob = b"".join(bytes(ID[c] for c in w) for w in word_list)
    offsets = np.cumsum([0] + [len(w) for w in word_list]).astype("<u4")
    info = json.dumps(info, ensure_ascii=False, sort_keys=True).encode()

    header_size = 8 + 4 + 4 + 4 + 4 + 10 * 4 + 4
    body = bytearray(b"\0" * (header_size + (-header_size % 8)))
    offs = []
    for part in (
        np.array([ord(c) for c in SYMBOLS], dtype="<u4").tobytes(),
        logp_book.astype("<f4").tobytes(),
        bow_book.astype("<f4").tobytes(),
        np.array([key(s) for s in entries], dtype="<u8").tobytes(),
        quantize(logp, logp_book).tobytes(),
        quantize(bow, bow_book, keep_zero=True).tobytes(),
        offsets.tobytes(),
        blob,
        bytes(freq[w] for w in word_list),
        info,
    ):
        align(body)
        offs.append(len(body))
        body.extend(part)
    header = b"WAOTYPE1" + struct.pack("<IBBBBII", 1, ORDER, V, MAX_WORD, 0, len(entries), len(word_list))
    header += struct.pack("<10I", *offs) + struct.pack("<I", len(info))
    body[: len(header)] = header
    return bytes(body), entries


def golden(model, tests, rng, n=500):
    """Contexts from the holdout, each paired with its true next character or a random symbol."""
    out = []
    lines = tests["chat"] + tests["formal"]
    while len(out) < n:
        line = rng.choice(lines)
        i = rng.randrange(len(line) + 1)
        c = line[i] if i < len(line) and rng.random() < 0.5 else rng.choice(SYMBOLS)
        out.append({"context": line[:i], "char": c, "logp": round(model.lookup(c, " " * (ORDER - 1) + line[:i]), 6)})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", type=Path, default=ROOT / ".model-cache/typing-corpora")
    ap.add_argument("--max-bytes", type=int, default=8_000_000)
    ap.add_argument("--max-words", type=int, default=40_000)
    args = ap.parse_args()

    import pythainlp

    corpus_dir = Path(pythainlp.__file__).parent / "corpus"
    tnc_path, words_path = corpus_dir / "tnc_freq.txt", corpus_dir / "words_th.txt"
    paths = fetch(args.cache)
    train, tests = load_corpora(paths)
    print(f"training on {len(train):,} lines, {sum(map(len, train)):,} chars", file=sys.stderr)
    model = Model(train)
    word_list, freq = words(train, tnc_path, words_path, args.max_words)

    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    for min_count in range(2, 100):
        model.prune(min_count)
        info = {
            "corpora": {name: {"url": url, "sha256": s} for name, (url, s) in SOURCES.items()},
            "words": {f"pythainlp {pythainlp.__version__} {p.name}": sha(p) for p in (words_path, tnc_path)},
            "order": ORDER,
            "min_count": min_count,
            "holdout": HOLDOUT,
            "split_seed": 0,
        }
        data, entries = serialize(model, word_list, freq, info)
        lengths = Counter(len(s) for s in entries)
        print(f"min count {min_count}: {len(entries):,} entries {dict(sorted(lengths.items()))}, "
              f"{len(word_list):,} words, {len(data):,} bytes", file=sys.stderr)
        if len(data) <= args.max_bytes:
            break
    RESOURCE.write_bytes(data)
    FIXTURES.mkdir(parents=True, exist_ok=True)
    for name, lines in tests.items():
        (FIXTURES / f"typing-holdout-{name}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    rows = (json.dumps(g, ensure_ascii=False) + "\n" for g in golden(model, tests, random.Random(7)))
    (FIXTURES / "typing-golden.jsonl").write_text("".join(rows), encoding="utf-8")
    print(f"wrote {RESOURCE.relative_to(ROOT)} ({len(data):,} bytes)", file=sys.stderr)


if __name__ == "__main__":
    main()
