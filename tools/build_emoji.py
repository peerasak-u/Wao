# /// script
# requires-python = ">=3.11"
# ///
"""Builds emoji.txt, the emoji panel's data, from Unicode's emoji-test.txt and CLDR's Thai annotations.

  uv run tools/build_emoji.py

Downloads emoji-test.txt for EMOJI_VERSION and CLDR's annotations/th.xml and annotationsDerived/th.xml for
CLDR_RELEASE into .model-cache/emoji and checks each sha256. Emoji 15.0 is the newest version that iOS 17.0, the
deployment target, draws in full (15.1 came with iOS 17.4). The keyboard has only Thai letters, so search reads the
Thai names and keywords: the short name first, then the keywords. CLDR keys drop U+FE0F, so lookups do too.

Keeps fully-qualified emoji only, which leaves out the skin tones and hair styles alone. Groups become the
categories of the iOS emoji keyboard, in its order: Smileys & Emotion and People & Body merge into smileys, and
activity comes before travel. An emoji in one skin tone, the same tone on every person in it, is filed under its
base emoji as one of five variants, lightest first. Mixed tones (two people, two tones) are left out.

Writes Packages/WaoCore/Sources/WaoCore/Resources/emoji.txt, UTF-8:
  # comment lines           where the data came from
  <category>                a line without a tab starts a category: smileys, animals, food, ...
  <glyph>\t<name>\t<thai keywords>[\t<tone 1>\t...\t<tone 5>]
                            keywords joined by |, empty when CLDR has no Thai annotation for the emoji
"""
import hashlib
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

EMOJI_VERSION = "15.0"
URL = f"https://www.unicode.org/Public/emoji/{EMOJI_VERSION}/emoji-test.txt"
SHA256 = "8445f23ac8388e096be19d0262e14fceff856ff52093f2356dc89485f1a853db"

CLDR_RELEASE = "release-47"
CLDR = f"https://raw.githubusercontent.com/unicode-org/cldr/{CLDR_RELEASE}/common"
ANNOTATIONS = [
    (f"{CLDR}/annotations/th.xml", "cdfb8f1e99253114875873d329984233cdd54d9cde8d2c83d3cba21c25d6386a", "th"),
    (f"{CLDR}/annotationsDerived/th.xml", "660b95961d0c25fc7ef3ffd1076f5086ca46f60f54d3a7148f55bac94df7ce2a", "th-derived"),
]

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / ".model-cache" / "emoji"
OUT = ROOT / "Packages/WaoCore/Sources/WaoCore/Resources/emoji.txt"

GROUPS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "smileys",
    "Animals & Nature": "animals",
    "Food & Drink": "food",
    "Activities": "activity",
    "Travel & Places": "travel",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}
ORDER = ["smileys", "animals", "food", "activity", "travel", "objects", "symbols", "flags"]
TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
VS16 = 0xFE0F


def fetch(url: str, sha256: str, cache: Path) -> bytes:
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(url) as response:
            cache.write_bytes(response.read())
    data = cache.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != sha256:
        sys.exit(f"{cache} has sha256 {digest}, expected {sha256}")
    return data


def strip_vs16(glyph: str) -> str:
    return glyph.replace(chr(VS16), "")


def thai_annotations() -> dict[str, list[str]]:
    """Unqualified glyph to its Thai short name, then its keywords, without repeats."""
    names: dict[str, str] = {}
    keywords: dict[str, list[str]] = {}
    for url, sha256, stem in ANNOTATIONS:
        data = fetch(url, sha256, CACHE_DIR / f"cldr-{CLDR_RELEASE}-{stem}.xml")
        for node in ET.fromstring(data).iter("annotation"):
            key = strip_vs16(node.get("cp", ""))
            text = (node.text or "").strip()
            if not key or not text or text == "↑↑↑":
                continue
            if node.get("type") == "tts":
                names.setdefault(key, text)
            else:
                keywords.setdefault(key, [k.strip() for k in text.split("|") if k.strip()])
    return {
        key: list(dict.fromkeys(([names[key]] if key in names else []) + keywords.get(key, [])))
        for key in names.keys() | keywords.keys()
    }


def main() -> None:
    categories: dict[str, list[dict]] = {c: [] for c in ORDER}
    bases: dict[tuple[int, ...], dict] = {}
    group = None
    counts = {"fully-qualified": 0, "mixed tones": 0}
    test = fetch(URL, SHA256, CACHE_DIR / f"emoji-test-{EMOJI_VERSION}.txt").decode("utf-8")
    thai = thai_annotations()
    for line in test.splitlines():
        if line.startswith("# group: "):
            group = line.removeprefix("# group: ")
            continue
        if not line or line.startswith("#"):
            continue
        fields, _, comment = line.partition("#")
        points, status = (f.strip() for f in fields.split(";"))
        if status != "fully-qualified":
            continue
        counts["fully-qualified"] += 1
        scalars = [int(p, 16) for p in points.split()]
        glyph = "".join(map(chr, scalars))
        # "# 😀 E1.0 grinning face": glyph, version, name.
        name = comment.strip().split(" ", 2)[2]
        key = tuple(s for s in scalars if s != VS16 and s not in TONES)
        tones = {s for s in scalars if s in TONES}
        if not tones:
            emoji = {"glyph": glyph, "name": name, "tones": [None] * 5}
            bases[key] = emoji
            categories[GROUPS[group]].append(emoji)
        elif len(tones) == 1:
            bases[key]["tones"][TONES.index(tones.pop())] = glyph
        else:
            counts["mixed tones"] += 1

    lines = [
        f"# Emoji {EMOJI_VERSION}, from {URL}",
        f"# sha256 {SHA256}. Unicode License V3, see THIRD_PARTY_NOTICES. Built by tools/build_emoji.py.",
        f"# Thai keywords from CLDR {CLDR_RELEASE}: " + ", ".join(f"{url} sha256 {sha}" for url, sha, _ in ANNOTATIONS),
    ]
    total = variants = annotated = 0
    for category in ORDER:
        lines.append(category)
        for emoji in categories[category]:
            tones = emoji["tones"]
            if any(tones) and not all(tones):
                sys.exit(f"{emoji['name']} has only some skin tones: {tones}")
            keywords = thai.get(strip_vs16(emoji["glyph"]), [])
            if any("|" in k or "\t" in k for k in keywords):
                sys.exit(f"{emoji['name']} has a keyword with a separator in it: {keywords}")
            lines.append("\t".join([emoji["glyph"], emoji["name"], "|".join(keywords), *(t for t in tones if t)]))
            total += 1
            annotated += 1 if keywords else 0
            variants += 5 if all(tones) else 0
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    accounted = total + variants + counts["mixed tones"]
    if accounted != counts["fully-qualified"]:
        sys.exit(f"accounted for {accounted} of {counts['fully-qualified']} fully-qualified emoji")
    print(f"Emoji {EMOJI_VERSION}: {counts['fully-qualified']} fully-qualified")
    print(f"  {total} in the grid, {variants} skin-tone variants, {counts['mixed tones']} mixed-tone left out")
    print(f"  {annotated} with Thai keywords, {total - annotated} without")
    for category in ORDER:
        print(f"  {category}: {len(categories[category])}")
    print(f"wrote {OUT.relative_to(ROOT)}: {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
