"""Correct-autograd capacity comparison on the delivered, unchanged 32px dataset.

Floating-point research only. Checkpoints are NOT FPGA weights or an accuracy promise.
Select checkpoints and rejection thresholds on validation; evaluate test only once.
"""
import argparse
import csv
import hashlib
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'objcls_work/v2_deps'))
import numpy as np
from PIL import Image
import torch
from torch import nn
from torch.nn import functional as F

CLASSES = ['unknown', 'cup', 'phone', 'figurine']


def metrics(y, pred):
    cm = np.zeros((4, 4), dtype=np.int64)
    np.add.at(cm, (y, pred), 1)
    f1 = []
    for k in range(1, 4):
        den = cm[k].sum() + cm[:, k].sum()
        f1.append(float(2 * cm[k, k] / den) if den else 0.)
    known = y != 0
    return dict(known_macro_f1=float(np.mean(f1)), per_class_f1=f1,
                known_accuracy=float(np.mean(pred[known] == y[known])),
                known_rejection=float(np.mean(pred[known] == 0)),
                unknown_false_accept=float(np.mean(pred[~known] != 0)),
                confusion_matrix=cm.tolist())


class Net(nn.Module):
    def __init__(self, name):
        super().__init__()
        channels = 8 if name == 'conv8' else 16
        self.conv1 = nn.Conv2d(3, channels, 3)
        self.conv2 = nn.Conv2d(16, 32, 3) if name != 'conv8' else None
        self.hidden = nn.Linear(6 * 6 * 32, 32) if self.conv2 else None
        self.fc = nn.Linear(32 if self.conv2 else 15 * 15 * 8, 4)

    def forward(self, x):
        x = F.max_pool2d(F.relu(self.conv1(x)), 2)
        if self.conv2:
            x = F.max_pool2d(F.relu(self.conv2(x)), 2)
        x = x.flatten(1)
        if self.hidden:
            x = F.relu(self.hidden(x))
        return self.fc(x)


@torch.no_grad()
def infer(net, x):
    net.eval()
    return torch.cat([net(a) for a in x.split(256)]).numpy()


def predict(logits, threshold):
    # Softmax margin is a software calibration experiment, NOT the v1 integer margin.
    p = torch.from_numpy(logits).softmax(1).numpy()
    order = np.argsort(-p, axis=1, kind='stable')
    margin = p[np.arange(len(p)), order[:, 0]] - p[np.arange(len(p)), order[:, 1]]
    pred = order[:, 0].copy()
    pred[margin < threshold] = 0
    return pred


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--epochs', type=int, default=25)
    ap.add_argument('--threads', type=int, default=4)
    ap.add_argument('--output', type=Path, default=ROOT / 'reports/object_classifier/capacity_experiment')
    args = ap.parse_args()
    torch.set_num_threads(args.threads)
    torch.set_num_interop_threads(1)
    args.output.mkdir(parents=True, exist_ok=True)
    delivery = ROOT / 'model_delivery/object_classifier_v1'
    manifest = delivery / 'dataset_manifest.csv'
    rows = list(csv.DictReader(manifest.open(encoding='utf-8-sig')))
    grouped = {}
    hashes, sessions = {}, {}
    for split in ['train', 'val', 'test']:
        rr = [r for r in rows if r['split'] == split]
        images = []
        for r in rr:
            path = delivery / 'dataset' / r['path']
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != r['sha256']:
                raise ValueError(f'Dataset hash changed: {path}')
            hashes.setdefault(digest, set()).add(split)
            sessions.setdefault(r['session_id'], set()).add(split)
            with Image.open(path) as im:
                array = np.asarray(im.convert('RGB'))
                if array.shape != (32, 32, 3):
                    raise ValueError('Input is not the delivered native 32x32 crop')
                images.append(array)
        x = torch.from_numpy(np.stack(images).transpose(0, 3, 1, 2).copy()).float() / 127.5 - 1
        y = torch.tensor([CLASSES.index(r['label']) for r in rr])
        grouped[split] = (x, y)
    audit = dict(manifest_sha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
                 images=len(rows), cross_split_exact_duplicates=sum(len(s) > 1 for s in hashes.values()),
                 cross_split_source_sessions=sum(len(s) > 1 for s in sessions.values()),
                 independent_physical_instances_verified=False,
                 note='Source-image sessions do not establish independent physical objects; near duplicates not checked.')
    (args.output / 'dataset_audit.json').write_text(json.dumps(audit, indent=2))
    print(json.dumps(audit), flush=True)
    x, y = grouped['train']
    counts = torch.bincount(y, minlength=4).float()
    weight = len(y) / (4 * counts)
    results = {}
    for name in ['conv8', 'conv16_conv32_fc32']:
        torch.manual_seed(20261019)
        np.random.seed(20261019)
        net = Net(name)
        optimizer = torch.optim.AdamW(net.parameters(), lr=.002, weight_decay=.0001)
        scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, args.epochs, eta_min=.00005)
        best = -1
        log = []
        start = time.monotonic()
        for epoch in range(args.epochs):
            net.train()
            total_loss = 0
            for indices in torch.randperm(len(y)).split(128):
                bx, by = x[indices].clone(), y[indices]
                flip = torch.rand(len(bx)) < .5
                bx[flip] = bx[flip].flip(-1)
                # Same light/translation augmentation for both architectures.
                gain = .6 + .8 * torch.rand(len(bx), 1, 1, 1)
                bx = ((bx + 1) * gain - 1).clamp(-1, 1)
                dx, dy = torch.randint(-2, 3, (2,)).tolist()
                bx = F.pad(bx, (2, 2, 2, 2), value=0)[:, :, 2+dy:34+dy, 2+dx:34+dx]
                optimizer.zero_grad(set_to_none=True)
                loss = F.cross_entropy(net(bx), by, weight=weight)
                loss.backward()
                optimizer.step()
                total_loss += float(loss.detach()) * len(indices)
            scheduler.step()
            logits = infer(net, grouped['val'][0])
            met = metrics(grouped['val'][1].numpy(), predict(logits, 0))
            row = dict(epoch=epoch+1, loss=total_loss/len(y), **met,
                       elapsed_seconds=round(time.monotonic()-start, 2))
            log.append(row)
            if met['known_macro_f1'] > best:
                best = met['known_macro_f1']
                torch.save(dict(state_dict=net.state_dict(), epoch=epoch+1, name=name), args.output / f'{name}.pt')
            (args.output / f'{name}_training_log.json').write_text(json.dumps(log, indent=2))
            print(name, json.dumps(row), flush=True)
        ckpt = torch.load(args.output / f'{name}.pt', weights_only=True)
        net.load_state_dict(ckpt['state_dict'])
        val_logits = infer(net, grouped['val'][0])
        thresholds = np.linspace(0, 1, 201)
        sweep = [(float(t), metrics(grouped['val'][1].numpy(), predict(val_logits, t))) for t in thresholds]
        # Model and optional threshold selection use validation alone.
        f1_t, _ = max(sweep, key=lambda item: item[1]['known_macro_f1'])
        feasible = [(t, m) for t, m in sweep if m['unknown_false_accept'] <= .10]
        constrained_t, _ = max(feasible, key=lambda item: item[1]['known_macro_f1'])
        policies = {'argmax': 0., 'validation_best_f1': f1_t, 'validation_unknown_FA_at_most_10pct': constrained_t}
        test_logits = infer(net, grouped['test'][0])
        results[name] = dict(best_epoch=ckpt['epoch'], parameters=sum(p.numel() for p in net.parameters()),
                             elapsed_seconds=round(time.monotonic()-start, 2),
                             policies={key: dict(threshold=t,
                                val=metrics(grouped['val'][1].numpy(), predict(val_logits,t)),
                                test=metrics(grouped['test'][1].numpy(), predict(test_logits,t)))
                                for key,t in policies.items()})
        np.savez(args.output / f'{name}_predictions.npz', val_logits=val_logits, val_labels=grouped['val'][1].numpy(),
                 test_logits=test_logits, test_labels=grouped['test'][1].numpy())
        report = dict(kind='floating_point_capacity_comparison_NOT_FPGA_EXPORT', seed=20261019,
                      torch_version=torch.__version__, epochs=args.epochs, dataset_audit=audit, results=results,
                      limitations=['Native 32x32 crops; no new image detail.', 'One seed, short training budget.',
                      'No quantization, integer RTL verification, synthesis, or camera integration for new networks.',
                      'Checkpoint selection uses unthresholded validation F1. Test is not used for selection.'])
        (args.output / 'results.json').write_text(json.dumps(report, indent=2))
        print('COMPLETED', name, json.dumps(results[name]), flush=True)


if __name__ == '__main__':
    main()
