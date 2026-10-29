"""Generate deterministic 160x96 calibration canvases from WIDER Face train.

Calibration drives the per-tensor power-of-two activation exponents; using
realistic face scenes (instead of a handful of stock photos) matches the
deployed input distribution.
"""
import argparse
import random
from pathlib import Path

import cv2
import numpy as np

from data import parse_wider_annotations, WiderCropDataset, FullSceneDataset


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--images', type=Path, required=True)
    ap.add_argument('--split', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--count', type=int, default=24)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    annotations = parse_wider_annotations(args.split)
    crops = WiderCropDataset(args.images, annotations, length=10 ** 9, seed=99, augment=False)
    full = FullSceneDataset(args.images, annotations)
    rng = random.Random(5)
    half = args.count // 2
    for i in range(args.count):
        if i < half:
            canvas, _ = crops[i]
            name = f'calib_crop_{i:02d}'
        else:
            canvas, _, _ = full[rng.randrange(len(full))]
            name = f'calib_full_{i - half:02d}'
        cv2.imwrite(str(args.out / f'{name}.png'), canvas)
    print(f'wrote {args.count} canvases to {args.out}')


if __name__ == '__main__':
    main()
