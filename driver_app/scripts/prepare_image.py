#!/usr/bin/env python3
"""
prepare_image.py

Dva rezima:
  prepare pretvara proizvoljnu sliku u grayscale PGM koji aplikacija cita
  draw ucrtava detekcije iz izlaznog fajla nazad na originalnu sliku

"""

import argparse
import sys

import cv2

# Iz vj_pkg.vhd: najsira skala koju row banke mogu primiti.
MAX_IMG_WIDTH = 360


def cmd_prepare(args):
    img = cv2.imread(args.source, cv2.IMREAD_GRAYSCALE)
    if img is None:
        sys.exit(f"ne mogu procitati '{args.source}'")

    h, w = img.shape

    if w > args.max_width:
        # Sirina preko MAX_IMG_WIDTH znaci da najsire skale ne staju u
        # row banke, pa se slika smanjuje jos na hostu.
        scale = args.max_width / w
        new_w = args.max_width
        new_h = max(1, int(round(h * scale)))
        img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
        print(f"smanjeno {w}x{h} -> {new_w}x{new_h} (MAX_IMG_WIDTH = {args.max_width})")
        h, w = img.shape

    # PGM P5 je binaran i opisuje samog sebe, pa aplikacija ne mora
    # pogadjati dimenzije.
    cv2.imwrite(args.dest, img)
    print(f"upisano {args.dest}: {w}x{h}, {w * h} piksela")

    # Kontrolni ispis:koliko skala hardver zaista obradi.
    scale = 1.0
    n = 0
    while True:
        sw, sh = int(round(w / scale)), int(round(h / scale))
        if sw < 24 or sh < 24:
            break
        if sw + 1 <= 512:
            n += 1
        scale *= args.factor
    print(f"pri faktoru {args.factor} bice obradjeno {n} skala")


def cmd_draw(args):
    img = cv2.imread(args.source, cv2.IMREAD_COLOR)
    if img is None:
        sys.exit(f"ne mogu procitati '{args.source}'")

    # Aplikacija radi nad pripremljenom (i potencijalno umanjenom) slikom, pa se
    # koordinate vracaju na originalnu rezoluciju istim odnosom.
    h, w = img.shape[:2]
    ratio = w / min(w, args.max_width) if w > args.max_width else 1.0

    count = 0
    with open(args.results) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            x, y, rw, rh = (int(round(int(v) * ratio)) for v in parts[:4])
            votes = parts[4] if len(parts) > 4 else "?"

            cv2.rectangle(img, (x, y), (x + rw, y + rh), (0, 255, 0), 2)
            cv2.putText(img, votes, (x, max(0, y - 5)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
            count += 1

    cv2.imwrite(args.dest, img)
    print(f"ucrtano {count} detekcija u {args.dest}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("prepare", help="slika -> grayscale PGM")
    p.add_argument("source")
    p.add_argument("dest")
    p.add_argument("--max-width", type=int, default=MAX_IMG_WIDTH)
    p.add_argument("--factor", type=float, default=1.2)
    p.set_defaults(func=cmd_prepare)

    p = sub.add_parser("draw", help="ucrtavanje detekcija na sliku")
    p.add_argument("source")
    p.add_argument("results")
    p.add_argument("dest")
    p.add_argument("--max-width", type=int, default=MAX_IMG_WIDTH)
    p.set_defaults(func=cmd_draw)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
