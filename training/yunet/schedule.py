"""Lower an integer yunet_n to FPGA ROM images (adapted from the archived
scripts/yunet_schedule.py + yunet_inplace_plan.py + yunet_schedule_inplace.py).

Writes program.hex, weights0-3.hex, bias.hex, shift.hex, yunet_heads.vh,
op_checks.txt, input.hex and op_NN.hex golden data into --out, never into
rtl/. The 64KiB alias-aware arena plan mirrors the production schedule.
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np

H, W = 96, 160


def first_fit_schedule(ops, heads):
    tensors = {'input': dict(shape=[H, W, 4], base=0, size=H * W * 4)}
    last = {}
    free = [(0, 131072)]
    live = {}
    allocations = {}

    def allocate(name, shape):
        size = (math.prod(shape) + 3) // 4 * 4
        for j, (base, n) in enumerate(free):
            if n >= size:
                free.pop(j)
                if n > size:
                    free.append((base + size, n - size))
                    free.sort()
                live[name] = (base, size)
                allocations[name] = dict(base=base, size=size, shape=shape)
                return base
        raise MemoryError((name, size, free))

    for i, op in enumerate(ops):
        for x in [op['src']] if isinstance(op['src'], str) else op['src']:
            last[x] = i
    for x in heads.values():
        last[x] = len(ops) + 1
    allocate('input', [H, W, 4])
    for i, op in enumerate(ops):
        srcs = [op['src']] if isinstance(op['src'], str) else op['src']
        allocate(op['dst'], op['shape'])
        for name in list(live):
            if last.get(name, -1) == i and name != op['dst'] and name in live:
                free.append(live.pop(name))
                free.sort()
                merged = []
                for b, n in free:
                    if merged and sum(merged[-1]) == b:
                        merged[-1] = (merged[-1][0], merged[-1][1] + n)
                    else:
                        merged.append((b, n))
                free[:] = merged
    return allocations


def inplace_plan(ops, heads):
    last = {}
    shapes = {'input': [96, 160, 4]}
    for i, o in enumerate(ops):
        for x in [o['src']] if isinstance(o['src'], str) else o['src']:
            last[x] = i
        shapes[o['dst']] = o['shape']
    for h in heads.values():
        last[h] = len(ops)
    free = [(0, 65536)]
    live = {}
    steps = []
    peak = 0

    def coalesce():
        free.sort()
        out = []
        for b, n in free:
            if out and sum(out[-1]) == b:
                out[-1] = (out[-1][0], out[-1][1] + n)
            else:
                out.append((b, n))
        free[:] = out

    def alloc(name, size):
        for j, (b, n) in enumerate(free):
            if n >= size:
                free.pop(j)
                if n > size:
                    free.append((b + size, n - size))
                coalesce()
                live[name] = (b, size)
                return b
        raise MemoryError((name, size, free))

    alloc('input', 96 * 160 * 4)
    for i, o in enumerate(ops):
        srcs = [o['src']] if isinstance(o['src'], str) else o['src']
        n = (math.prod(o['shape']) + 3) // 4 * 4
        alias = None
        strategy = 'separate allocation'
        for src in srcs:
            if last[src] != i:
                continue
            ih, iw, ci = shapes[src]
            oh, ow, co = o['shape']
            b, old = live[src]
            if o['op'] == 'conv':
                spatial = o['pad'] != 0
                if spatial and ci < 4:
                    continue
                if spatial and ow * co > o['stride'] * iw * ci:
                    continue
                mode = 'three source rows' if spatial else \
                    'pixel cache, reverse traversal' if co > ci else 'pixel cache, forward traversal'
            elif o['op'] == 'maxpool':
                mode = 'four reads before compacted write'
            elif o['op'] == 'resize':
                mode = 'reverse traversal'
            else:
                mode = 'read both operands before write'
            if n > old:
                match = next((j for j, (fb, fn) in enumerate(free)
                              if fb == b + old and fn >= n - old), None)
                if match is None:
                    continue
                fb, fn = free.pop(match)
                if fn > n - old:
                    free.append((b + n, fn - (n - old)))
            elif n < old:
                free.append((b + n, old - n))
            del live[src]
            live[o['dst']] = (b, n)
            alias = src
            strategy = mode
            coalesce()
            break
        if alias is None:
            b = alloc(o['dst'], n)
        peak = max(peak, max(base + size for base, size in live.values()))
        steps.append(dict(index=i, name=o['name'], dst=o['dst'], base=b,
                          bytes=n, alias=alias, strategy=strategy))
        for src in srcs:
            if last[src] == i and src in live:
                free.append(live.pop(src))
                coalesce()
    return steps, peak


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--qdir', type=Path, required=True, help='quantize.py output dir')
    ap.add_argument('--out', type=Path, required=True, help='staging dir for ROMs')
    args = ap.parse_args()
    out = args.out
    out.mkdir(parents=True, exist_ok=True)

    net = json.loads((args.qdir / 'network.json').read_text(encoding='utf-8'))
    ops = net['operations']
    heads = net['heads']
    weights = np.load(args.qdir / 'integer_model.npz')
    allocations = first_fit_schedule(ops, heads)

    romweights = []
    descriptors = []
    for i, op in enumerate(ops):
        srcs = [op['src']] if isinstance(op['src'], str) else op['src']
        src = allocations[srcs[0]]
        base = allocations[op['dst']]['base']
        ih, iw, ci = src['shape']
        oh, ow, co = op['shape']
        opcode = {'conv': 1, 'maxpool': 2, 'resize': 3, 'add': 4}[op['op']]
        k = 1
        stride = 1
        pad = 0
        dw = 0
        relu = 0
        wb = 0
        bb = 0
        s1 = 0
        s2 = 0
        if opcode == 1:
            original_ci = 3 if op['src'] == 'input' else (1 if op['group'] > 1 else ci)
            convs = [o for o in ops if o['op'] == 'conv']
            k_i = convs.index(op)
            count = (convs[k_i + 1]['weight_offset'] - op['weight_offset']
                     if k_i + 1 < len(convs) else len(weights['weights']) - op['weight_offset'])
            k = round(math.sqrt(count / (co * original_ci)))
            w = weights['weights'][op['weight_offset']:op['weight_offset'] + count].reshape(co, k, k, original_ci)
            if op['src'] == 'input':
                w = np.pad(w, ((0, 0), (0, 0), (0, 0), (0, 1)))
            if op['group'] > 1:
                # Depthwise taps go channel-major ([tap][oc]) so four adjacent
                # output channels of one tap land in the four weight banks of a
                # single ROM word; the scheduler consumes them in one beat.
                co4 = (co + 3) // 4 * 4
                w = np.pad(w.reshape(co, k * k).T, ((0, 0), (0, co4 - co))).reshape(1, k, k, -1)
            while len(romweights) % 4:
                romweights.append(0)
            wb = len(romweights)
            romweights.extend(w.reshape(-1).tolist())
            bb = op['bias_offset']
            stride = op['stride']
            pad = op['pad']
            dw = int(op['group'] > 1)
            relu = int(op['relu'])
        else:
            s1 = op['shifts'][0]
            s2 = op['shifts'][-1]
        fields = [(opcode, 0, 4), (src['base'], 4, 17),
                  (allocations[srcs[-1]]['base'] if len(srcs) > 1 else 0, 21, 17),
                  (base, 38, 17), (iw, 55, 8), (ih, 63, 8), (ow, 71, 8), (oh, 79, 8),
                  (ci, 87, 7), (co, 94, 7),
                  (k == 3, 101, 1), (stride == 2, 102, 1), (pad, 103, 1), (dw, 104, 1),
                  (relu, 105, 1), (wb, 106, 16), (bb, 122, 11), (s1, 133, 7), (s2, 140, 7),
                  (op['src'] == 'input', 147, 1)]
        word = 0
        for value, shift, bits in fields:
            word |= (int(value) & ((1 << bits) - 1)) << shift
        descriptors.append(word)

    # alias-aware in-place rebases (the production 64KiB plan)
    steps, peak = inplace_plan(ops, heads)
    bases = {'input': 0}
    words = []
    checks = []
    for word, step, op in zip(descriptors, steps, ops):
        srcs = [op['src']] if isinstance(op['src'], str) else op['src']

        def field(v, pos, bits):
            nonlocal word
            mask = ((1 << bits) - 1) << pos
            word = (word & ~mask) | ((v << pos) & mask)

        field(bases[srcs[0]], 4, 17)
        field(bases[srcs[-1]] if len(srcs) > 1 else 0, 21, 17)
        field(step['base'], 38, 17)
        field(int(step['alias'] is not None), 148, 1)
        field(int(step['alias'] is not None and 'reverse' in step['strategy']), 149, 1)
        words.append(word)
        bases[op['dst']] = step['base']
        checks.append(f"{step['base']} {math.prod(op['shape'])}")

    while len(romweights) % 4:
        romweights.append(0)
    for bank in range(4):
        np.savetxt(out / f'weights{bank}.hex',
                   np.array(romweights[bank::4], np.int8).astype(np.uint8), fmt='%02x')
    np.savetxt(out / 'bias.hex', weights['bias'].astype(np.uint32), fmt='%08x')
    np.savetxt(out / 'shift.hex', weights['shift'].astype(np.uint8) & 127, fmt='%02x')
    (out / 'program.hex').write_text('\n'.join(f'{x:040x}' for x in words) + '\n', encoding='ascii')

    trace = np.load(args.qdir / 'trace_reference.npz')
    raw = np.pad(trace['input'], ((0, 0), (0, 0), (0, 1)))
    np.savetxt(out / 'input.hex', raw.astype(np.uint8).reshape(-1), fmt='%02x')
    for i, op in enumerate(ops):
        np.savetxt(out / f'op_{i:02}.hex', trace[op['dst']].astype(np.uint8).reshape(-1), fmt='%02x')
    (out / 'op_checks.txt').write_text('\n'.join(checks) + '\n', encoding='ascii')
    lines = ['// Generated alias-aware head offsets.']
    for name, src in heads.items():
        lines.append(f"localparam [16:0] HEAD_{name.upper()}=17'd{bases[src]};")
    (out / 'yunet_heads.vh').write_text('\n'.join(lines) + '\n', encoding='ascii')

    report = dict(ops=len(ops), weight_bank_depth=len(romweights) // 4,
                  arena_peak_bytes=peak, aliases=sum(s['alias'] is not None for s in steps),
                  head_bases={k: bases[v] for k, v in heads.items()})
    (out / 'schedule_report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
