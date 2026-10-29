"""Compare candidate weights on WIDER Face derived 160x96 evaluation sets.

Candidates:
  old_float  - original opencv_zoo ONNX via onnxruntime (accuracy ceiling of shipped ROMs)
  old_int8   - original ONNX through this repo's power-of-two integer pipeline
  new_float  - fine-tuned ONNX via onnxruntime
  new_int8   - fine-tuned ONNX through the same integer pipeline

Metrics: multi-box recall/precision@IoU .5 and the deployment-relevant
single-best-box hit rate (the RTL decoder keeps exactly one box).
Usage: python evaluate.py --images <WIDER_val/images> --split <val bbx_gt>
       --old <orig.onnx> --new <finetuned.onnx> --old-int8 <dir> --new-int8 <dir>
       --out <report.json> [--val-images 600]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort

sys.path.insert(0, str(Path(__file__).parent))

from data import (FullSceneDataset, parse_wider_annotations, make_crop_eval_set,
                  VISIBLE_W, VISIBLE_H, CANVAS_H, MIN_FACE)

STRIDES = (8, 16, 32)
GRIDS = {f'{kind}_{s}': (96 // s, 160 // s, c)
         for s in STRIDES for kind, c in (('cls', 1), ('obj', 1), ('bbox', 4))}


def iou(a, b):
    x = max(0.0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
    y = max(0.0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    inter = x * y
    return inter / max(1e-12, a[2] * a[3] + b[2] * b[3] - inter)


def decode(head_maps, threshold=0.65, iou_threshold=0.3):
    """head_maps: {name: (H,W,C) float array} with cls_/obj_/bbox_ per stride."""
    boxes = []
    for stride in STRIDES:
        cls = np.clip(head_maps[f'cls_{stride}'].reshape(-1), 0, 1)
        obj = np.clip(head_maps[f'obj_{stride}'].reshape(-1), 0, 1)
        reg = head_maps[f'bbox_{stride}'].reshape(-1, 4)
        for i, score in enumerate(np.sqrt(cls * obj)):
            if score < threshold:
                continue
            cx = (i % (VISIBLE_W // stride) + reg[i, 0]) * stride
            cy = (i // (VISIBLE_W // stride) + reg[i, 1]) * stride
            bw = np.exp(np.clip(reg[i, 2], -12, 12)) * stride
            bh = np.exp(np.clip(reg[i, 3], -12, 12)) * stride
            boxes.append([float(cx - bw / 2), float(cy - bh / 2), float(bw), float(bh), float(score)])
    keep = []
    for b in sorted(boxes, key=lambda b: -b[4]):
        if all(iou(b, k) < iou_threshold for k in keep):
            keep.append(b)
    return keep


class OnnxRunner:
    def __init__(self, path):
        from quantize import load_graph, session
        m, _ = load_graph(path)          # rewrite the cached 640x640 input to 96x160
        self.sess = session(m)
        self.out_names = [o.name for o in self.sess.get_outputs() if not o.name.startswith('kps')]

    def heads(self, canvas):
        raw = self.sess.run(None, {'input': canvas.transpose(2, 0, 1)[None].astype(np.float32)})
        all_names = [o.name for o in self.sess.get_outputs()]
        out = {}
        for name, v in zip(all_names, raw):
            if name.startswith('kps'):
                continue
            # Graph tail: Transpose(0,2,3,1) then Reshape -> (1, H*W*C, 1) in HWC order.
            out[name] = v.reshape(GRIDS[name])
        return out


class Int8Runner:
    """Integer pipeline runner produced by quantize.py (ops_for_infer.pkl)."""

    def __init__(self, qdir):
        import pickle
        from quantize import infer
        with open(Path(qdir) / 'ops_for_infer.pkl', 'rb') as f:
            blob = pickle.load(f)
        self.ops = blob['ops']
        self.scales = blob['scales']
        self.heads_map = blob['heads']
        self._infer = infer

    def heads(self, canvas):
        tensors, _, _ = self._infer(canvas, self.ops)
        out = {}
        for name, src in self.heads_map.items():
            v = tensors[src].astype(float) * 2.0 ** self.scales[src]
            if name.startswith(('cls', 'obj')):
                v = 1.0 / (1.0 + np.exp(-v))
            out[name] = v
        return out


def score_image(runner, canvas, gt_boxes):
    boxes = decode(runner.heads(canvas))
    matched = np.zeros(len(gt_boxes), bool)
    tp = 0
    for b in boxes:
        best_j, best_v = -1, 0.3
        for j, g in enumerate(gt_boxes):
            v = iou(b, g.tolist())
            if v >= best_v:
                best_j, best_v = j, v
        if best_j >= 0 and not matched[best_j]:
            matched[best_j] = True
            tp += 1
    fp = len(boxes) - tp
    # single-best-box: deployment behavior, aim at the largest GT face
    single = 0
    if boxes:
        gt_main = gt_boxes[np.argmax(gt_boxes[:, 2] * gt_boxes[:, 3])].tolist() if len(gt_boxes) else None
        single = int(iou(boxes[0], gt_main) >= 0.5) if gt_main is not None else 0
    return tp, fp, matched.sum(), single, len(gt_boxes)


def eval_full_scene(runner, images, limit):
    tp = fp = gt_total = gt_hit = 0
    single_hits = single_total = 0
    for i in range(min(limit, len(images))):
        canvas, boxes, relpath = images[i]
        if len(boxes) == 0:
            continue
        t, f, hits, single, n = score_image(runner, canvas, boxes)
        tp += t
        fp += f
        gt_total += n
        gt_hit += hits
        single_hits += single
        single_total += 1
    prec = tp / max(1, tp + fp)
    rec = gt_hit / max(1, gt_total)
    return dict(images=single_total, recall=rec, precision=prec,
                gt_faces=gt_total, single_best_hit_rate=single_hits / max(1, single_total))


def eval_crop(runner, crop_eval, per_size):
    per_size_report = {}
    total_hit = total = 0
    for size, items in sorted(crop_eval.items()):
        use = items[:per_size]
        hits = 0
        for canvas, boxes, _ in use:
            boxes_d = decode(runner.heads(canvas), threshold=0.5)
            hits += int(any(iou(b, boxes[0].tolist()) >= 0.5 for b in boxes_d)) if len(boxes_d) else 0
        per_size_report[size] = hits / max(1, len(use))
        total_hit += hits
        total += len(use)
    return dict(per_size=per_size_report, overall=total_hit / max(1, total))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--images', type=Path, required=True)
    ap.add_argument('--split', type=Path, required=True)
    ap.add_argument('--old', type=Path, required=True)
    ap.add_argument('--new', type=Path, required=True)
    ap.add_argument('--old-int8', type=Path)
    ap.add_argument('--new-int8', type=Path)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--val-images', type=int, default=600)
    ap.add_argument('--per-size', type=int, default=30)
    args = ap.parse_args()

    annotations = parse_wider_annotations(args.split)
    full = FullSceneDataset(args.images, annotations, limit=args.val_images)
    crops = make_crop_eval_set(args.images, annotations, per_size=args.per_size)

    candidates = [('old_float', OnnxRunner(args.old)), ('new_float', OnnxRunner(args.new))]
    if args.old_int8:
        candidates.append(('old_int8', Int8Runner(args.old_int8)))
    if args.new_int8:
        candidates.append(('new_int8', Int8Runner(args.new_int8)))

    report = {}
    for name, runner in candidates:
        report[name] = dict(full_scene=eval_full_scene(runner, full, args.val_images),
                            crop=eval_crop(runner, crops, args.per_size))
        print(name, json.dumps(report[name]['full_scene']), flush=True)
        print(name, 'crop overall', report[name]['crop']['overall'],
              {k: round(v, 2) for k, v in report[name]['crop']['per_size'].items()}, flush=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('wrote', args.out)


if __name__ == '__main__':
    main()
