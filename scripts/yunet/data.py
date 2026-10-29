"""WIDER Face parsing and 160x96 training-sample generation.

The FPGA consumes a 160x96 BGR canvas: the 1280x720 camera field is 8x box-
averaged to 160x90 and rows 90..95 are zero. Training samples must look like
that canvas: a 16:9 crop resized to 160x90, placed at the top, six zero rows.
Crops are anchored on a randomly chosen face with a target on-canvas face
size drawn from the scale range the three stride-8/16/32 heads can express.
"""
import math
import random
from pathlib import Path

import cv2
import numpy as np

VISIBLE_W, VISIBLE_H, CANVAS_H = 160, 90, 96
MIN_FACE = 7          # below this a face cannot be encoded on stride 8 cells
MAX_FACE = 86         # above this it no longer fits the visible canvas usefully


def parse_wider_annotations(split_txt):
    """Return {relpath: [(x1,y1,w,h,invalid,blur), ...]} from a bbx_gt file."""
    images = {}
    lines = [l.strip() for l in Path(split_txt).read_text(encoding='utf-8').splitlines()]
    i = 0
    while i < len(lines):
        name = lines[i]
        count = int(lines[i + 1])
        i += 2
        if count == 0 and i < len(lines) and lines[i] and not '/' in lines[i] \
                and lines[i].split()[0].lstrip('-').isdigit():
            i += 1  # some zero-face entries carry a dummy "0 0 0 0 0 0 0 0 0 0" row
        faces = []
        for _ in range(count):
            vals = [int(v) for v in lines[i].split()]
            x1, y1, w, h = vals[0:4]
            invalid = vals[7] if len(vals) >= 8 else 0
            blur = vals[4] if len(vals) >= 5 else 0
            faces.append((x1, y1, w, h, invalid, blur))
            i += 1
        images[name] = faces
    return images


def load_image(img_root, relpath):
    img = cv2.imread(str(Path(img_root) / relpath))
    if img is None:
        raise FileNotFoundError(relpath)
    return img


class WiderCropDataset:
    """Random face-anchored crops rendered onto the 160x96 canvas."""

    def __init__(self, img_root, annotations, length, seed=20261028,
                 augment=True, size_choices=(10, 12, 14, 17, 20, 24, 29, 34, 40, 48, 57, 68, 80)):
        self.img_root = Path(img_root)
        self.images = sorted(annotations.keys())
        self.ann = annotations
        self.length = length
        self.rng = random.Random(seed)
        self.augment = augment
        self.size_choices = size_choices
        self._cache = {}

    def __len__(self):
        return self.length

    def _read(self, relpath):
        if relpath not in self._cache:
            if len(self._cache) > 400:
                self._cache.clear()
            self._cache[relpath] = load_image(self.img_root, relpath)
        return self._cache[relpath]

    def __getitem__(self, idx):
        for _ in range(50):
            relpath = self.rng.choice(self.images)
            faces = [f for f in self.ann[relpath]
                     if f[2] >= 4 and f[3] >= 4 and f[4] == 0]
            if not faces:
                continue
            anchor = self.rng.choice(faces)
            img = self._read(relpath)
            ih, iw = img.shape[:2]
            ax, ay, aw, ah = anchor[0:4]
            target = self.rng.choice(self.size_choices)
            scale = target / max(aw, ah)
            # 16:9 crop in source pixels that maps onto the 160x90 visible area.
            crop_w = min(iw, int(round(VISIBLE_W / scale)))
            crop_h = min(ih, int(round(VISIBLE_H / scale)))
            if crop_w < 16 or crop_h < 9:
                continue
            cx = min(max(ax + aw / 2, crop_w / 2), iw - crop_w / 2)
            cy = min(max(ay + ah / 2, crop_h / 2), ih - crop_h / 2)
            jx = self.rng.uniform(-0.28, 0.28) * crop_w * 0.5 if self.augment else 0
            jy = self.rng.uniform(-0.28, 0.28) * crop_h * 0.5 if self.augment else 0
            x0 = int(round(min(max(cx + jx - crop_w / 2, 0), iw - crop_w)))
            y0 = int(round(min(max(cy + jy - crop_h / 2, 0), ih - crop_h)))
            crop = img[y0:y0 + crop_h, x0:x0 + crop_w]
            canvas = cv2.resize(crop, (VISIBLE_W, VISIBLE_H), interpolation=cv2.INTER_AREA)

            boxes = []
            for (fx, fy, fw, fh, invalid, blur) in self.ann[relpath]:
                bx1 = (fx - x0) * VISIBLE_W / crop_w
                by1 = (fy - y0) * VISIBLE_H / crop_h
                bw = fw * VISIBLE_W / crop_w
                bh = fh * VISIBLE_H / crop_h
                keep = (bx1 + bw > 0 and by1 + bh > 0 and bx1 < VISIBLE_W and by1 < VISIBLE_H
                        and bw >= MIN_FACE and bh >= MIN_FACE and bw <= MAX_FACE and bh <= MAX_FACE
                        and invalid == 0 and blur < 2 and bx1 >= -2 and by1 >= -2)
                if keep:
                    boxes.append((min(max(bx1, 0), VISIBLE_W - 1),
                                  min(max(by1, 0), VISIBLE_H - 1), bw, bh))
                elif bw >= MIN_FACE * 0.5 and bh >= MIN_FACE * 0.5 and bx1 < VISIBLE_W and by1 < VISIBLE_H:
                    boxes.append(None)  # too small / blurry: ignore region marker
            boxes = [b for b in boxes if b is not None] or None
            if not boxes:
                continue
            if self.augment:
                canvas = augment_canvas(canvas, self.rng)
                if self.rng.random() < 0.5:
                    canvas = canvas[:, ::-1].copy()
                    boxes = [(VISIBLE_W - x - w, y, w, h) for (x, y, w, h) in boxes]
            sample = np.zeros((CANVAS_H, VISIBLE_W, 3), np.uint8)
            sample[:VISIBLE_H] = canvas
            return sample, np.asarray(boxes, np.float32)
        raise RuntimeError('could not build a sample')


def augment_canvas(img, rng):
    if rng.random() < 0.8:
        alpha = rng.uniform(0.7, 1.3)
        beta = rng.uniform(-28, 28)
        img = np.clip(img.astype(np.float32) * alpha + beta, 0, 255).astype(np.uint8)
    if rng.random() < 0.3:
        gamma = rng.uniform(0.7, 1.4)
        table = np.array([(i / 255.0) ** gamma * 255 for i in range(256)], np.uint8)
        img = cv2.LUT(img, table)
    if rng.random() < 0.25:
        k = rng.choice((3, 3, 5))
        img = cv2.GaussianBlur(img, (k, k), 0)
    if rng.random() < 0.3:
        img = np.clip(img.astype(np.float32) + rng.uniform(-9, 9), 0, 255).astype(np.uint8)
    return img


class FullSceneDataset:
    """Whole WIDER images reduced to the canvas, for deployment-like evaluation."""

    def __init__(self, img_root, annotations, limit=None):
        self.img_root = Path(img_root)
        self.items = [(k, v) for k, v in sorted(annotations.items())]
        if limit:
            self.items = self.items[:limit]

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        relpath, faces = self.items[idx]
        img = load_image(self.img_root, relpath)
        ih, iw = img.shape[:2]
        scale = min(VISIBLE_W / iw, VISIBLE_H / ih)
        nw, nh = max(1, round(iw * scale)), max(1, round(ih * scale))
        small = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_AREA)
        ox, oy = (VISIBLE_W - nw) // 2, (VISIBLE_H - nh) // 2
        canvas = np.zeros((CANVAS_H, VISIBLE_W, 3), np.uint8)
        canvas[oy:oy + nh, ox:ox + nw] = small
        boxes = []
        for (fx, fy, fw, fh, invalid, blur) in faces:
            x = ox + fx * scale
            y = oy + fy * scale
            w, h = fw * scale, fh * scale
            if invalid == 0 and w >= MIN_FACE and h >= MIN_FACE:
                boxes.append((x, y, w, h))
        return canvas, np.asarray(boxes, np.float32).reshape(-1, 4), relpath


def make_crop_eval_set(img_root, annotations, per_size=40, seed=7):
    """Deterministic single-face crops binned by on-canvas face size."""
    rng = random.Random(seed)
    sizes = (10, 14, 20, 28, 40, 56, 80)
    by_size = {s: [] for s in sizes}
    names = sorted(annotations.keys())
    rng.shuffle(names)
    for relpath in names:
        faces = [f for f in annotations[relpath]
                 if f[2] >= 8 and f[3] >= 8 and f[4] == 0 and f[5] < 2]
        if not faces:
            continue
        img = None
        for anchor in faces:
            aw, ah = anchor[2], anchor[3]
            for s in sizes:
                if len(by_size[s]) >= per_size:
                    continue
                scale = s / max(aw, ah)
                if scale <= 0 or scale > 1:
                    continue
                if img is None:
                    img = load_image(img_root, relpath)
                ih, iw = img.shape[:2]
                crop_w, crop_h = min(iw, round(VISIBLE_W / scale)), min(ih, round(VISIBLE_H / scale))
                if crop_w < 16 or crop_h < 9:
                    continue
                cx = min(max(anchor[0] + aw / 2, crop_w / 2), iw - crop_w / 2)
                cy = min(max(anchor[1] + ah / 2, crop_h / 2), ih - crop_h / 2)
                x0 = int(round(min(max(cx - crop_w / 2, 0), iw - crop_w)))
                y0 = int(round(min(max(cy - crop_h / 2, 0), ih - crop_h)))
                crop = img[y0:y0 + crop_h, x0:x0 + crop_w]
                canvas = cv2.resize(crop, (VISIBLE_W, VISIBLE_H), interpolation=cv2.INTER_AREA)
                box = ((anchor[0] - x0) * VISIBLE_W / crop_w,
                       (anchor[1] - y0) * VISIBLE_H / crop_h,
                       aw * VISIBLE_W / crop_w, ah * VISIBLE_H / crop_h)
                out = np.zeros((CANVAS_H, VISIBLE_W, 3), np.uint8)
                out[:VISIBLE_H] = canvas
                by_size[s].append((out, np.asarray([box], np.float32), relpath))
                break
        if all(len(v) >= per_size for v in by_size.values()):
            break
    return by_size


# Official-model behavior at the 160x96 canvas: stride 8 carries every face
# size (probed 10..80 px), stride 16 adds a secondary signal below ~16 px,
# stride 32 stays dark. Match that assignment so fine-tuning refines the
# warm start instead of fighting it.
def assign_strides(w, h):
    side = max(w, h)
    return (8, 16) if side < 16 else (8,)
