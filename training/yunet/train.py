"""Fine-tune yunet_n on WIDER Face crops rendered as 160x96 canvases.

Warm start = official opencv_zoo weights. Supervision is FCOS-style: cls BCE
over grid cells, centerness BCE on positives, L1 on (offset_x, offset_y,
log w, log h). The optimizer only ever sees losses on the cls/obj/bbox
branches; kps parameters stay at their pretrained values.

Usage: python train.py --images <WIDER_train/images> --split <bbx_gt txt>
                        --work <dir> [--steps 9000] [--batch 16]
"""
import argparse
import math
import queue
import threading
import time
from pathlib import Path

import numpy as np
import torch

from yunet_torch import YuNetN, decode_heads, STRIDES
from data import (WiderCropDataset, parse_wider_annotations, make_crop_eval_set,
                  VISIBLE_W, VISIBLE_H, CANVAS_H, assign_strides)

IGNORE, NEG, POS = 0, 1, 2


def build_targets(boxes_list, device):
    """Per-level cls/obj/box targets from a batch of (N_i,4) float box arrays."""
    targets = []
    for level, stride in enumerate(STRIDES):
        gh, gw = CANVAS_H // stride, VISIBLE_W // stride
        cls = torch.zeros(len(boxes_list), 1, gh, gw, device=device)
        obj = torch.zeros(len(boxes_list), 1, gh, gw, device=device)
        box = torch.zeros(len(boxes_list), 4, gh, gw, device=device)
        pos = torch.zeros(len(boxes_list), 1, gh, gw, dtype=torch.bool, device=device)
        for n, boxes in enumerate(boxes_list):
            for (bx, by, bw, bh) in boxes:
                x, y, w, h = float(bx), float(by), float(bw), float(bh)
                if stride not in assign_strides(w, h):
                    continue
                # Center sampling: positives are cells inside the central half of the
                # box. Full-box positives produced broad warm score maps and a
                # precision collapse in the first fine-tuning iteration; small faces
                # whose central half contains no cell fall back to the nearest cell.
                cx_lo, cx_hi = x + 0.25 * w, x + 0.75 * w
                cy_lo, cy_hi = y + 0.25 * h, y + 0.75 * h
                cells = []
                best = None
                best_d = 1e9
                for yy in range(max(0, int(y / stride)), min(gh - 1, int((y + h) / stride)) + 1):
                    for xx in range(max(0, int(x / stride)), min(gw - 1, int((x + w) / stride)) + 1):
                        px = (xx + 0.5) * stride
                        py = (yy + 0.5) * stride
                        if not (x <= px <= x + w and y <= py <= y + h):
                            continue
                        d = (px - (x + w / 2)) ** 2 + (py - (y + h / 2)) ** 2
                        if d < best_d:
                            best_d, best = d, (yy, xx)
                        if cx_lo <= px <= cx_hi and cy_lo <= py <= cy_hi:
                            cells.append((yy, xx))
                if not cells and best is not None:
                    cells = [best]
                for yy, xx in cells:
                    cls[n, 0, yy, xx] = 1.0
                    obj[n, 0, yy, xx] = 1.0
                    box[n, 0, yy, xx] = (x + w / 2) / stride - xx
                    box[n, 1, yy, xx] = (y + h / 2) / stride - yy
                    box[n, 2, yy, xx] = math.log(w / stride)
                    box[n, 3, yy, xx] = math.log(h / stride)
                    pos[n, 0, yy, xx] = True
        targets.append((cls, obj, box, pos))
    return targets


def batch_loss(heads, targets):
    losses = {}
    cls_total = obj_total = box_total = 0.0
    pos_total = 0
    for level, (cls_t, obj_t, box_t, pos) in enumerate(targets):
        cls_logits = heads['cls'][level]
        obj_logits = heads['obj'][level]
        box_pred = heads['box'][level]
        pos = pos.expand_as(cls_logits)
        npos = int(pos.sum())
        if npos:
            neg = (~pos) & (cls_t < 0.5)
            nneg = max(1, int(neg.sum()))
            w = torch.zeros_like(cls_t)
            w[pos] = 1.0
            w[neg] = min(3.0 * npos / nneg, 1.0)
            cls_total = cls_total + torch.nn.functional.binary_cross_entropy_with_logits(
                cls_logits, cls_t, weight=w)
            obj_total = obj_total + torch.nn.functional.binary_cross_entropy_with_logits(
                obj_logits[pos], obj_t[pos])
            box_total = box_total + torch.nn.functional.smooth_l1_loss(
                box_pred[pos.expand_as(box_pred)].view(-1, 4),
                box_t[pos.expand_as(box_t)].view(-1, 4), beta=0.5)
            pos_total += npos
        else:
            cls_total = cls_total + torch.nn.functional.binary_cross_entropy_with_logits(cls_logits, cls_t)
    losses['cls'] = float(cls_total)
    losses['obj'] = float(obj_total) if pos_total else 0.0
    losses['box'] = float(box_total) if pos_total else 0.0
    return cls_total + obj_total + 2.0 * box_total, losses, pos_total


class BatchPrefetcher:
    """Worker threads render sample batches while the main thread trains."""

    def __init__(self, img_root, annotations, batch, seed, workers=3):
        self.queue = queue.Queue(maxsize=8)
        self.stop = threading.Event()
        self.threads = []
        for w in range(workers):
            ds = WiderCropDataset(img_root, annotations, length=10 ** 9, seed=seed + 1000 * w + 7)
            t = threading.Thread(target=self._produce, args=(ds, batch), daemon=True)
            t.start()
            self.threads.append(t)

    def _produce(self, ds, batch):
        i = 0
        while not self.stop.is_set():
            canvases, gts = [], []
            for _ in range(batch):
                c, b = ds[i]
                canvases.append(c)
                gts.append(b)
                i += 1
            self.queue.put((np.stack(canvases), gts))

    def next(self):
        return self.queue.get()


@torch.no_grad()
def quick_eval(model, crop_eval, device, per_size=12, threshold=0.5):
    model.eval()
    hits = total = 0
    for size, items in sorted(crop_eval.items()):
        for canvas, boxes, _ in items[:per_size]:
            x = torch.from_numpy(canvas.transpose(2, 0, 1)[None].astype(np.float32)).to(device)
            heads = model(x)
            best = decode_heads(heads, threshold=threshold, single=True)
            gt = boxes[0]
            if best is None:
                total += 1
                continue
            from yunet_torch import _iou
            hits += int(_iou(best, gt.tolist()) >= 0.5)
            total += 1
    model.train()
    return hits / max(1, total)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--images', type=Path, required=True)
    ap.add_argument('--split', type=Path, required=True)
    ap.add_argument('--eval-images', type=Path,
                    help='WIDER val images; checkpoint selection uses val crops when given '
                         '(train-crop selection is optimistic — see run 1)')
    ap.add_argument('--eval-split', type=Path)
    ap.add_argument('--work', type=Path, required=True)
    ap.add_argument('--steps', type=int, default=9000)
    ap.add_argument('--batch', type=int, default=16)
    ap.add_argument('--lr', type=float, default=7e-5)
    ap.add_argument('--warm', type=int, default=400)
    ap.add_argument('--seed', type=int, default=20261028)
    ap.add_argument('--threads', type=int, default=8)
    ap.add_argument('--device', default='auto',
                    help='auto picks cuda, then mps (Apple Silicon), then cpu')
    args = ap.parse_args()

    torch.manual_seed(args.seed)
    torch.set_num_threads(max(1, args.threads))
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available()
                              else 'mps' if getattr(torch.backends, 'mps', None) is not None
                              and torch.backends.mps.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    args.work.mkdir(parents=True, exist_ok=True)

    model = YuNetN().load_onnx().to(device)
    annotations = parse_wider_annotations(args.split)
    if args.eval_images and args.eval_split:
        crop_eval = make_crop_eval_set(args.eval_images,
                                       parse_wider_annotations(args.eval_split), per_size=16)
        print('checkpoint selection: VAL crops', flush=True)
    else:
        crop_eval = make_crop_eval_set(args.images, annotations, per_size=16)
        print('checkpoint selection: TRAIN crops (pass --eval-images/--eval-split for honest selection)',
              flush=True)
    prefetch = BatchPrefetcher(args.images, annotations, args.batch, args.seed)

    trainable = [p for k, p in model.p.items() if 'kps' not in k]
    opt = torch.optim.AdamW(trainable, lr=args.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.OneCycleLR(
        opt, max_lr=args.lr, total_steps=args.steps,
        pct_start=min(0.3, args.warm / args.steps))

    print(f'device={device} params={sum(p.numel() for p in model.p.values())} '
          f'trainable={sum(p.numel() for p in trainable)}', flush=True)
    baseline = quick_eval(model, crop_eval, device)
    print(f'baseline official-weights crop recall@0.5 = {baseline:.4f}', flush=True)
    best = -1.0
    log = open(args.work / 'train_log.csv', 'a', encoding='utf-8')
    log.write('step,loss,cls,obj,box,pos,recall,seconds\n')

    t0 = time.time()
    for step in range(1, args.steps + 1):
        canvases, gts = prefetch.next()
        batch = torch.from_numpy(canvases.transpose(0, 3, 1, 2).astype(np.float32)).to(device)
        targets = build_targets(gts, device)
        heads = model(batch)
        loss, parts, npos = batch_loss(heads, targets)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(trainable, 5.0)
        opt.step()
        sched.step()
        if step % 100 == 0 or step == 1:
            msg = (f'step {step}/{args.steps} loss={float(loss):.4f} '
                   f'cls={parts["cls"]:.4f} obj={parts["obj"]:.4f} box={parts["box"]:.4f} '
                   f'pos={npos} lr={sched.get_last_lr()[0]:.2e} {time.time()-t0:.0f}s')
            print(msg, flush=True)
            log.write(f'{step},{float(loss):.5f},{parts["cls"]:.5f},{parts["obj"]:.5f},'
                      f'{parts["box"]:.5f},{npos},,{time.time()-t0:.1f}\n')
            log.flush()
        if step % 1500 == 0 or step == args.steps:
            recall = quick_eval(model, crop_eval, device)
            print(f'  eval@{step}: crop recall={recall:.4f} (best {max(best, recall):.4f})', flush=True)
            log.seek(0, 2)
            if recall >= best:
                best = recall
                torch.save({k: v.detach().cpu() for k, v in model.p.items()},
                           args.work / 'best_weights.pt')
                (args.work / 'best_meta.json').write_text(
                    f'{{"step": {step}, "crop_recall": {recall}, "baseline": {baseline}}}\n',
                    encoding='utf-8')
    torch.save({k: v.detach().cpu() for k, v in model.p.items()}, args.work / 'final_weights.pt')
    (args.work / 'final_meta.json').write_text(
        f'{{"step": {args.steps}, "best_recall": {best}, "baseline": {baseline}}}\n', encoding='utf-8')
    print(f'done. baseline={baseline:.4f} best={best:.4f}', flush=True)


if __name__ == '__main__':
    main()
