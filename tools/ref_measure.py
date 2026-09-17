"""Measure the F1 cockpit reference picture and cut zoom crops for design work.

Usage: python tools/ref_measure.py <image.jpg> <out_dir>

Prints row profiles that locate the halo bar, the horizon and the cockpit
props, and writes enlarged crops so the shapes can be judged directly.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def profile(img: np.ndarray, out_dir: Path):
    h, w, _ = img.shape
    lum = img.mean(axis=2) / 255.0
    dark = (lum < 0.22).mean(axis=1)
    bright = (lum > 0.72).mean(axis=1)
    print(f"  size {w}x{h}")
    print("  row%  dark%  bright%  meanRGB")
    for pct in range(0, 101, 2):
        y = min(int(pct / 100.0 * h), h - 1)
        row = img[y]
        print(f"  {pct:4d}  {dark[y]*100:5.1f}  {bright[y]*100:6.1f}   "
              f"{row[:,0].mean():5.1f} {row[:,1].mean():5.1f} {row[:,2].mean():5.1f}")
    print("  col%  dark%  meanRGB   (over the top 35 % of the frame)")
    top = img[: int(h * 0.35)]
    tl = top.mean(axis=2) / 255.0
    for pct in range(0, 101, 5):
        x = min(int(pct / 100.0 * w), w - 1)
        print(f"  {pct:4d}  {(tl[:, x] < 0.22).mean()*100:5.1f}   "
              f"{top[:, x, 0].mean():5.1f} {top[:, x, 1].mean():5.1f} {top[:, x, 2].mean():5.1f}")


def crop(img: Image.Image, box, name: str, out_dir: Path, scale: int = 3):
    x0, y0, x1, y1 = box
    c = img.crop(box)
    c = c.resize((c.width * scale, c.height * scale), Image.NEAREST)
    path = out_dir / name
    c.save(path)
    print(f"  crop {name} box={box} -> {c.size}")


def main():
    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img)
    profile(arr, out_dir)
    w, h = img.size
    crop(img, (0, 0, w, int(h * 0.30)), "ref_A_top.png", out_dir, 2)
    crop(img, (0, int(h * 0.33), int(w * 0.22), int(h * 0.55)), "ref_B_mirrorL.png", out_dir, 4)
    crop(img, (int(w * 0.78), int(h * 0.33), w, int(h * 0.55)), "ref_C_mirrorR.png", out_dir, 4)
    crop(img, (int(w * 0.34), int(h * 0.38), int(w * 0.72), int(h * 0.60)), "ref_D_dash.png", out_dir, 4)
    crop(img, (int(w * 0.26), int(h * 0.52), int(w * 0.78), h), "ref_E_wheel.png", out_dir, 3)
    crop(img, (int(w * 0.24), int(h * 0.55), int(w * 0.42), h), "ref_F_handL.png", out_dir, 5)


if __name__ == "__main__":
    main()
