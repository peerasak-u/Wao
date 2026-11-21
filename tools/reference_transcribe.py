"""Reference transcriber for iapp/OpenThai2.0-ASR-Streaming-ONNX (int8).

Mirrors NeMo's AudioToMelSpectrogramPreprocessor as configured in the model's
model_config.yaml (128 mels, n_fft 512, win 400 symmetric Hann, hop 160,
preemph 0.97, power 2, slaney mel, log(x + 2**-24), no normalisation,
center=True with constant padding, frames >= len//hop masked to 0) and
NeMo's greedy RNN-T loop (max 2 symbols per frame, blank as SOS).

Usage:
  python -I tools/reference_transcribe.py --model-dir .model-cache/int8 \
      [--lang th-TH|th-mix] [--dump DIR] [--threads 1] clip.wav ...
"""
import argparse
import json
import pathlib
import sys
import time

import numpy as np
import onnxruntime as ort
import soundfile as sf

SAMPLE_RATE = 16000
N_FFT = 512
WIN = 400
HOP = 160
N_MELS = 128
PREEMPH = 0.97
LOG_GUARD = 2.0**-24
PROMPTS = {"th-TH": 32, "th-mix": 63}
MAX_SYMBOLS = 2


def hz_to_mel(f):
    f = np.asarray(f, dtype=np.float64)
    f_sp = 200.0 / 3
    mels = f / f_sp
    min_log_hz, min_log_mel, logstep = 1000.0, 1000.0 / f_sp, np.log(6.4) / 27.0
    return np.where(f >= min_log_hz, min_log_mel + np.log(np.maximum(f, 1e-10) / min_log_hz) / logstep, mels)


def mel_to_hz(m):
    m = np.asarray(m, dtype=np.float64)
    f_sp = 200.0 / 3
    freqs = f_sp * m
    min_log_hz, min_log_mel, logstep = 1000.0, 1000.0 / f_sp, np.log(6.4) / 27.0
    return np.where(m >= min_log_mel, min_log_hz * np.exp(logstep * (m - min_log_mel)), freqs)


def mel_filterbank():
    fftfreqs = np.linspace(0, SAMPLE_RATE / 2, 1 + N_FFT // 2)
    mel_f = mel_to_hz(np.linspace(hz_to_mel(0.0), hz_to_mel(SAMPLE_RATE / 2), N_MELS + 2))
    fdiff = np.diff(mel_f)
    ramps = mel_f[:, None] - fftfreqs[None, :]
    lower = -ramps[:-2] / fdiff[:-1, None]
    upper = ramps[2:] / fdiff[1:, None]
    weights = np.maximum(0, np.minimum(lower, upper))
    weights *= (2.0 / (mel_f[2 : N_MELS + 2] - mel_f[:N_MELS]))[:, None]
    return weights.astype(np.float32)


def features(audio):
    """audio: float32 [-1, 1) mono 16 kHz -> (mel [128, frames] float32, valid_frames)."""
    x = np.asarray(audio, dtype=np.float64)
    x = np.concatenate([x[:1], x[1:] - PREEMPH * x[:-1]])
    x = np.pad(x, (N_FFT // 2, N_FFT // 2))
    frames = 1 + (len(x) - N_FFT) // HOP
    n = np.arange(WIN)
    window = np.zeros(N_FFT)
    window[(N_FFT - WIN) // 2 : (N_FFT - WIN) // 2 + WIN] = 0.5 - 0.5 * np.cos(2 * np.pi * n / (WIN - 1))
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(frames)[:, None]
    spec = np.fft.rfft(x[idx] * window[None, :], n=N_FFT, axis=1)
    power = (spec.real**2 + spec.imag**2).T
    mel = np.log(mel_filterbank().astype(np.float64) @ power + LOG_GUARD).astype(np.float32)
    valid = len(audio) // HOP
    mel[:, valid:] = 0.0
    return mel, valid


class Transcriber:
    def __init__(self, model_dir, threads=1):
        model_dir = pathlib.Path(model_dir)
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = threads
        opts.inter_op_num_threads = 1
        self.encoder = ort.InferenceSession(str(model_dir / "encoder.int8.onnx"), opts, providers=["CPUExecutionProvider"])
        self.decoder = ort.InferenceSession(str(model_dir / "decoder_joint.onnx"), opts, providers=["CPUExecutionProvider"])
        self.tokens = (model_dir / "tokens.txt").read_text(encoding="utf-8").split("\n")[:-1]
        self.blank = len(self.tokens)

    def encode(self, mel, valid, lang):
        enc, enc_len = self.encoder.run(
            ["encoded", "encoded_length"],
            {
                "audio_signal": mel[None],
                "length": np.array([valid], dtype=np.int64),
                "prompt_index": np.array([PROMPTS[lang]], dtype=np.int64),
            },
        )
        return enc[0, : int(enc_len[0])]

    def greedy(self, encoded, blank_bias):
        state1 = np.zeros((2, 1, 640), dtype=np.float32)
        state2 = np.zeros((2, 1, 640), dtype=np.float32)
        last = self.blank
        out = []
        for frame in encoded:
            f = frame.reshape(1, 1024, 1).astype(np.float32)
            for _ in range(MAX_SYMBOLS):
                logits, _, s1, s2 = self.decoder.run(
                    None,
                    {
                        "encoder_outputs": f,
                        "targets": np.array([[last]], dtype=np.int32),
                        "target_length": np.array([1], dtype=np.int32),
                        "input_states_1": state1,
                        "input_states_2": state2,
                    },
                )
                scores = logits.reshape(-1).astype(np.float64)
                scores[self.blank] += blank_bias
                k = int(np.argmax(scores))
                if k == self.blank:
                    break
                out.append(k)
                last, state1, state2 = k, s1, s2
        return out

    def text(self, ids):
        pieces = [self.tokens[i] for i in ids if not (self.tokens[i].startswith("<") and self.tokens[i].endswith(">"))]
        return "".join(pieces).replace("▁", " ").strip()

    def transcribe(self, audio, lang="th-TH"):
        mel, valid = features(audio)
        encoded = self.encode(mel, valid, lang)
        # The service's "standard" mode: -1.0, clips under 2 s at -2.5, empty output again at -4.0.
        bias = -2.5 if len(audio) < 2 * SAMPLE_RATE else -1.0
        ids = self.greedy(encoded, bias)
        if not self.text(ids):
            ids = self.greedy(encoded, -4.0)
        return mel, valid, ids


def cer(ref, hyp):
    r, h = ref.replace(" ", ""), hyp.replace(" ", "")
    d = list(range(len(h) + 1))
    for i, rc in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, hc in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (rc != hc))
    return d[len(h)] / max(len(r), 1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model-dir", required=True)
    p.add_argument("--lang", default="th-TH", choices=sorted(PROMPTS))
    p.add_argument("--threads", type=int, default=1)
    p.add_argument("--dump", help="directory for <name>.mel.f32 and <name>.json fixtures")
    p.add_argument("wavs", nargs="+")
    a = p.parse_args()
    t0 = time.perf_counter()
    tr = Transcriber(a.model_dir, a.threads)
    print(f"load {time.perf_counter() - t0:.2f}s", file=sys.stderr)
    total_cer = []
    for wav in map(pathlib.Path, a.wavs):
        audio, sr = sf.read(str(wav), dtype="float32")
        assert sr == SAMPLE_RATE and audio.ndim == 1, f"{wav}: need 16 kHz mono"
        t0 = time.perf_counter()
        mel, valid, ids = tr.transcribe(audio, a.lang)
        dt = time.perf_counter() - t0
        hyp = tr.text(ids)
        ref_path = wav.with_suffix(".txt")
        ref = ref_path.read_text(encoding="utf-8").strip() if ref_path.exists() else None
        c = cer(ref, hyp) if ref is not None else None
        if c is not None:
            total_cer.append(c)
        dur = len(audio) / SAMPLE_RATE
        print(json.dumps({"wav": wav.name, "ref": ref, "hyp": hyp, "cer": c, "audio_s": round(dur, 3),
                          "decode_s": round(dt, 3), "rtf": round(dt / dur, 3)}, ensure_ascii=False))
        if a.dump:
            d = pathlib.Path(a.dump)
            d.mkdir(parents=True, exist_ok=True)
            mel.astype("<f4").tofile(d / f"{wav.stem}.{a.lang}.mel.f32")
            (d / f"{wav.stem}.{a.lang}.json").write_text(json.dumps(
                {"wav": wav.name, "lang": a.lang, "frames": int(mel.shape[1]), "valid": valid,
                 "tokens": ids, "text": hyp}, ensure_ascii=False))
    if total_cer:
        print(f"mean CER {np.mean(total_cer):.3f}", file=sys.stderr)


if __name__ == "__main__":
    main()
