"""Runs wao-transcribe over PoodPim's code-switching eval set, in the layout its eval.py scores.

  cd <eval folder>                      # holds src/, clips/ and clips.json from `eval.py prepare`
  python3 tools/asr_eval.py run NAME [wao-transcribe options]    # writes out/NAME/hyp.json and timing.json
  python3 tools/asr_eval.py timing NAME...                       # decoder seconds and real-time factor
  python3 <PoodPim>/tools/asr-eval/eval.py report NAME...        # CER and English-word recall

PoodPim's eval.py (github.com/thirawat/PoodPim, tools/asr-eval) does the scoring, so the numbers are
comparable with PoodPim's own.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path.cwd()
CLI = Path(__file__).resolve().parents[1] / "Packages/WaoCore/.build/release/wao-transcribe"


def run(name, options):
    meta = json.loads((HERE / "clips.json").read_text())
    files = [str(HERE / "clips" / f"{m['name']}.wav") for m in meta]
    out = subprocess.run([str(CLI), *options, *files], capture_output=True, text=True, check=True).stdout
    lines = [json.loads(l) for l in out.splitlines()]
    d = HERE / "out" / name
    d.mkdir(parents=True, exist_ok=True)
    hyps = {Path(l["file"]).stem: l["text"] for l in lines}
    (d / "hyp.json").write_text(json.dumps(hyps, ensure_ascii=False, indent=1))
    (d / "timing.json").write_text(json.dumps(lines, ensure_ascii=False, indent=1))
    print(name, len(hyps), "transcripts")


def timing(names):
    print(f"{'condition':<22}{'audio s':>9}{'encoder s':>11}{'decoder s':>11}{'total s':>9}{'RTF':>7}")
    for n in names:
        lines = json.loads((HERE / "out" / n / "timing.json").read_text())
        audio = sum(l["audio_seconds"] for l in lines)
        enc = sum(l["encoder_seconds"] for l in lines)
        dec = sum(l["decoder_seconds"] for l in lines)
        total = sum(l["seconds"] for l in lines)
        print(f"{n:<22}{audio:>9.1f}{enc:>11.2f}{dec:>11.2f}{total:>9.2f}{total / audio:>7.3f}")


if __name__ == "__main__":
    if sys.argv[1] == "run":
        run(sys.argv[2], sys.argv[3:])
    elif sys.argv[1] == "timing":
        timing(sys.argv[2:])
    else:
        sys.exit(__doc__)
