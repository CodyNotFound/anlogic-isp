"""Power-of-two integer lowering for a yunet_n ONNX (adapted from scripts/yunet_integer.py).

Same math as the archived production tool — per-output-channel power-of-two
weight exponents, per-tensor activation exponents calibrated on real canvases,
int8 weights / int32 bias / per-channel requant shift, half-up rounding and
saturation. Parameterized model/calibration/output paths, plus the RTL shift
contracts (conv 1..31, add 0/1, pool/resize 0) as hard gates.
"""
import argparse
import copy
import json
import math
import pickle
from pathlib import Path

import cv2
import numpy as np
import onnx
from onnx import helper, numpy_helper
import onnxruntime as ort

W, H = 160, 96
MAX_WEIGHT_BYTES = 12373 * 4
MAX_BIAS_ENTRIES = 1524

scales = {}          # module-level for eval reuse; set by lower/lower_from


def attributes(n):
    return {a.name: helper.get_attribute_value(a) for a in n.attribute}


def exponent(maximum, limit=127):
    return max(-24, int(math.ceil(math.log2(max(float(maximum) / limit, 2. ** -24)))))


def rounded_shift(a, s):
    a = np.asarray(a, dtype=np.int64)
    return (a + (1 << (s - 1))) >> s if s > 0 else a << (-s)


def convolution(x, w, pad=0, stride=1, group=1):
    kh, kw = w.shape[1:3]
    h, wi, ci = x.shape
    co = w.shape[0]
    p = np.pad(x, ((pad, pad), (pad, pad), (0, 0)))
    windows = np.lib.stride_tricks.sliding_window_view(p, (kh, kw), axis=(0, 1))[::stride, ::stride]
    if group == 1:
        return np.einsum('xycij,oijc->xyo', windows, w, optimize=True)
    assert group == ci == co and w.shape[-1] == 1
    return np.einsum('xycij,cij->xyc', windows, w[:, :, :, 0], optimize=True)


def load_graph(model_path):
    m = onnx.load(str(model_path))
    weights = {a.name: numpy_helper.to_array(a) for a in m.graph.initializer}
    outputs = [o.name for o in m.graph.output if not o.name.startswith('kps')]
    needed = set(outputs)
    nodes = []
    for n in reversed(m.graph.node):
        if any(o in needed for o in n.output):
            nodes.append(n)
            needed.update(n.input)
    nodes.reverse()
    del m.graph.node[:]
    m.graph.node.extend(nodes)
    kept = [a for a in m.graph.initializer if a.name in needed]
    del m.graph.initializer[:]
    m.graph.initializer.extend(kept)
    kept = [a for a in m.graph.output if a.name in outputs]
    del m.graph.output[:]
    m.graph.output.extend(kept)
    del m.graph.value_info[:]
    dims = m.graph.input[0].type.tensor_type.shape.dim
    dims[2].dim_value = H
    dims[3].dim_value = W
    for o in m.graph.output:
        for d in o.type.tensor_type.shape.dim:
            d.ClearField('dim_value')
            d.ClearField('dim_param')
    return m, weights


def session(m, intermediate=False):
    m = copy.deepcopy(m)
    if intermediate:
        names = {o.name for o in m.graph.output}
        for n in m.graph.node:
            if n.op_type in ('Conv', 'Relu', 'MaxPool', 'Resize', 'Add') and n.output[0] not in names:
                m.graph.output.append(helper.make_tensor_value_info(n.output[0], onnx.TensorProto.FLOAT, None))
    opt = ort.SessionOptions()
    opt.intra_op_num_threads = 4
    return ort.InferenceSession(m.SerializeToString(), sess_options=opt, providers=['CPUExecutionProvider'])


def calibrate(m, images):
    run = session(m, True)
    ranges = {}
    shapes = {}
    canvases = images.values() if isinstance(images, dict) else images
    for a in canvases:
        values = run.run(None, {'input': a.transpose(2, 0, 1)[None].astype(np.float32)})
        for meta, value in zip(run.get_outputs(), values):
            ranges[meta.name] = max(ranges.get(meta.name, 0), float(np.max(np.abs(value))))
            shapes[meta.name] = list(value.shape)
    return {name: exponent(v * 1.15) for name, v in ranges.items()}, shapes


def lower(m, weights, calib_scales, shapes):
    global scales
    operations = []
    aliases = {'input': 'input'}
    all_weights = []
    all_bias = []
    all_shifts = []
    consumers = {}
    for n in m.graph.node:
        for v in n.input:
            consumers[v] = consumers.get(v, 0) + 1
    nodes = list(m.graph.node)
    calib_scales = dict(calib_scales)
    calib_scales['input'] = 0
    for i, n in enumerate(nodes):
        op = n.op_type
        a = attributes(n)
        src = [aliases.get(x, x) for x in n.input]
        dest = n.output[0]
        if op == 'Relu':
            continue
        if op == 'Conv':
            relu = i + 1 < len(nodes) and nodes[i + 1].op_type == 'Relu' \
                and nodes[i + 1].input[0] == dest and consumers[dest] == 1
            if relu:
                dest = nodes[i + 1].output[0]
                aliases[n.output[0]] = dest
                aliases[dest] = dest
            wf = weights[n.input[1]].transpose(0, 2, 3, 1)
            bf = weights[n.input[2]]
            we = np.array([exponent(np.max(np.abs(v))) for v in wf], np.int32)
            wq = np.stack([np.clip(np.rint(v / 2. ** e), -127, 127).astype(np.int8) for v, e in zip(wf, we)])
            ie = calib_scales[src[0]]
            oe = calib_scales[dest]
            bq = np.rint(bf / np.power(2., we + ie)).astype(np.int64)
            if np.any(np.abs(bq) > 2147483647):
                raise OverflowError(n.name + ' bias')
            shift = oe - ie - we
            shape = shapes[dest]
            oh, ow = shape[2:]
            ci = wf.shape[-1]
            co = len(wf)
            kh, kw = wf.shape[1:3]
            operations.append(dict(op='conv', name=n.name, src=src[0], dst=dest,
                                   shape=[oh, ow, co], weights=wq, bias=bq.astype(np.int32),
                                   shift=shift, relu=bool(relu), pad=a['pads'][0],
                                   stride=a['strides'][0], group=a['group'],
                                   kernel=[kh, kw], ci=ci,
                                   weight_offset=len(all_weights), bias_offset=len(all_bias),
                                   macs=oh * ow * co * ci * kh * kw))
            all_weights.extend(wq.reshape(-1).tolist())
            all_bias.extend(bq.tolist())
            all_shifts.extend(shift.tolist())
        elif op in ('MaxPool', 'Resize', 'Add'):
            operations.append(dict(op=op.lower(), name=n.name, src=src[:2] if op == 'Add' else src[:1],
                                   dst=dest, shape=[shapes[dest][2], shapes[dest][3], shapes[dest][1]],
                                   shifts=[calib_scales[dest] - calib_scales[x]
                                           for x in (src[:2] if op == 'Add' else src[:1])]))
        elif op in ('Transpose', 'Reshape', 'Sigmoid'):
            aliases[dest] = src[0]
        else:
            raise ValueError('Unsupported ' + op)
    heads = {o.name: aliases[o.name] for o in m.graph.output}
    scales = dict(calib_scales)
    return operations, calib_scales, heads, np.array(all_weights, np.int8), \
        np.array(all_bias, np.int32), np.array(all_shifts, np.int32)


def lower_from(net, npz):
    """Rebuild in-memory ops (with arrays) from network.json + integer_model.npz."""
    global scales
    wq = npz['weights']
    bq = npz['bias']
    sh = npz['shift']
    ops = []
    for op in net['operations']:
        op = dict(op)
        if op['op'] == 'conv':
            co = op['shape'][2]
            op['weights'] = np.zeros(0, np.int64)  # filled in the second pass
            op['bias'] = bq[op['bias_offset']:op['bias_offset'] + co]
            op['shift'] = sh[op['bias_offset']:op['bias_offset'] + co]
        ops.append(op)
    convs = [o for o in ops if o['op'] == 'conv']
    for k, o in enumerate(convs):
        start = o['weight_offset']
        end = convs[k + 1]['weight_offset'] if k + 1 < len(convs) else len(wq)
        kh, kw = o['kernel']
        o['weights'] = wq[start:end].reshape(o['shape'][2], kh, kw, o['ci']).astype(np.int64)
    scales = dict(net['scales'])
    return ops, net['scales'], net['heads'], wq, bq, sh


def infer(a, ops):
    tensors = {'input': a.astype(np.int64)}
    maxacc = 0
    saturation = {}
    for op in ops:
        if op['op'] == 'conv':
            acc = convolution(tensors[op['src']], op['weights'].astype(np.int64),
                              op['pad'], op['stride'], op['group']) + op['bias']
            maxacc = max(maxacc, int(np.max(np.abs(acc))))
            if np.any(np.abs(acc) > 2147483647):
                raise OverflowError(op['name'] + ' accumulator')
            v = np.stack([rounded_shift(acc[:, :, i], int(s)) for i, s in enumerate(op['shift'])], axis=2)
            low = 0 if op['relu'] else -128
        elif op['op'] == 'maxpool':
            x = tensors[op['src'][0]]
            v = np.maximum.reduce([x[0::2, 0::2], x[1::2, 0::2], x[0::2, 1::2], x[1::2, 1::2]])
            v = rounded_shift(v, op['shifts'][0])
            low = -128
        elif op['op'] == 'resize':
            v = np.repeat(np.repeat(tensors[op['src'][0]], 2, 0), 2, 1)
            v = rounded_shift(v, op['shifts'][0])
            low = -128
        elif op['op'] == 'add':
            e = max(op['shifts'])
            v = sum(tensors[x] << (e - s) for x, s in zip(op['src'], op['shifts']))
            v = rounded_shift(v, e)
            low = -128
        else:
            raise ValueError(op['op'])
        saturation[op['dst']] = float(np.mean((v < -128) | (v > 127)))
        tensors[op['dst']] = np.clip(v, low, 127).astype(np.int64)
    return tensors, maxacc, saturation


def verify_lowering(m, weights, ops, a):
    run = session(m, True)
    raw = run.run(None, {'input': a.transpose(2, 0, 1)[None].astype(np.float32)})
    expected = {o.name: v[0].transpose(1, 2, 0) for o, v in zip(run.get_outputs(), raw) if v.ndim == 4}
    nodes = {n.name: n for n in m.graph.node}
    t = {'input': a.astype(np.float32)}
    errors = {}
    for op in ops:
        if op['op'] == 'conv':
            n = nodes[op['name']]
            w = weights[n.input[1]].transpose(0, 2, 3, 1)
            v = convolution(t[op['src']], w, op['pad'], op['stride'], op['group']) + weights[n.input[2]]
            if op['relu']:
                v = np.maximum(v, 0)
        elif op['op'] == 'maxpool':
            x = t[op['src'][0]]
            v = np.maximum.reduce([x[::2, ::2], x[1::2, ::2], x[::2, 1::2], x[1::2, 1::2]])
        elif op['op'] == 'resize':
            v = np.repeat(np.repeat(t[op['src'][0]], 2, 0), 2, 1)
        else:
            v = t[op['src'][0]] + t[op['src'][1]]
        want = expected[op['dst']]
        error = float(np.max(np.abs(v - want)))
        if error > 1e-3 + float(np.max(np.abs(want))) * 2e-4:
            raise AssertionError((op['name'], error))
        errors[op['name']] = error
        t[op['dst']] = v
    return errors


def check_contracts(ops, wq, bq):
    problems = []
    for op in ops:
        if op['op'] == 'conv':
            bad = [int(s) for s in op['shift'] if not (0 <= int(s) <= 31)]
            if bad:
                problems.append(f"{op['name']}: conv shifts outside 0..31 e.g. {bad[:3]}")
        elif op['op'] == 'add':
            if not all(s in (0, 1) for s in op['shifts']):
                problems.append(f"{op['name']}: add shifts {op['shifts']} not in {{0,1}}")
        elif op['op'] in ('maxpool', 'resize'):
            if op['shifts'] != [0]:
                problems.append(f"{op['name']}: {op['op']} shifts {op['shifts']} != [0]")
    if len(wq) > MAX_WEIGHT_BYTES:
        problems.append(f'weights {len(wq)} exceed ROM budget {MAX_WEIGHT_BYTES}')
    if len(bq) > MAX_BIAS_ENTRIES:
        problems.append(f'bias {len(bq)} exceeds ROM budget {MAX_BIAS_ENTRIES}')
    return problems


def load_calib_images(calib_dir):
    images = []
    for p in sorted(Path(calib_dir).glob('*.png')):
        a = cv2.imread(str(p))
        if a is not None:
            images.append(a)
    if not images:
        raise FileNotFoundError(f'no calibration canvases in {calib_dir}')
    return images


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--model', type=Path, required=True)
    ap.add_argument('--calib-dir', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--scale-reference', type=Path, help='Freeze deployed activation/head exponents')
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    m, weights = load_graph(args.model)
    images = load_calib_images(args.calib_dir)
    calib_scales, shapes = calibrate(m, images)
    if args.scale_reference:
        reference=json.loads(args.scale_reference.read_text(encoding='utf-8'))['scales']
        if not set(calib_scales).issubset(reference):raise ValueError('Scale contract does not cover this graph')
        calib_scales=reference
    ops, final_scales, heads, wq, bq, shifts = lower(m, weights, calib_scales, shapes)

    float_errors = verify_lowering(m, weights, ops, images[0])
    if max(float_errors.values())>1e-3:raise ValueError('Float lowering does not match ONNX')
    problems = check_contracts(ops, wq, bq)

    run = session(m)
    trace = None
    agreement = {}
    saturation_max = {}
    for a in images[:6]:
        raw = run.run(None, {'input': a.transpose(2, 0, 1)[None].astype(np.float32)})
        t, acc, sat = infer(a, ops)
        for name,value in sat.items():saturation_max[name]=max(saturation_max.get(name,0),value)
        if trace is None:
            trace = t
        for name, src in heads.items():
            qv = t[src].astype(float) * 2. ** final_scales[src]
            fv = {o.name: v for o, v in zip(run.get_outputs(), raw)}[name]
            stride = int(name.rsplit('_', 1)[1])
            c = 4 if name.startswith('bbox') else 1
            fv = fv.reshape(H // stride, W // stride, c)  # graph tail flattens to HWC
            if name.startswith(('cls', 'obj')):
                qv = 1 / (1 + np.exp(-qv))
                # ONNX detection outputs already contain sigmoid probabilities.
            agreement[name] = float(np.max(np.abs(qv - fv)))

    serial = [{k: (v.tolist() if isinstance(v, np.ndarray) else v) for k, v in op.items()
               if k not in ('weights', 'bias')} for op in ops]
    (args.out / 'network.json').write_text(json.dumps(dict(
        operations=serial, scales=final_scales, heads=heads), indent=2) + '\n', encoding='utf-8')
    np.savez_compressed(args.out / 'integer_model.npz', weights=wq, bias=bq, shift=shifts)
    with open(args.out / 'ops_for_infer.pkl', 'wb') as f:
        pickle.dump(dict(ops=ops, scales=final_scales, heads=heads), f)
    np.savez_compressed(args.out / 'trace_reference.npz',
                        **{k: v.astype(np.int16) for k, v in trace.items()})
    np.savetxt(args.out / 'weights.hex', wq.astype(np.uint8), fmt='%02x')
    np.savetxt(args.out / 'bias.hex', bq.astype(np.uint32), fmt='%08x')

    report = dict(model=str(args.model), calib_images=len(images),
                  operations=len(ops), weight_bytes=int(len(wq)),
                  lowered_float_max_abs_error=max(float_errors.values()),
                  worst_integer_head_deviation=max(agreement.values()),
                  contract_problems=problems,
                  calibration_saturation_max=saturation_max,
                  frozen_scale_reference=bool(args.scale_reference))
    (args.out / 'quantize_report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    summary={k:v for k,v in report.items() if k!='calibration_saturation_max'}
    summary['worst_saturation_fraction']=max(saturation_max.values(),default=0)
    print(json.dumps(summary,indent=2))
    if problems:
        raise SystemExit('RTL contract violations; ROMs NOT eligible for the FPGA')


if __name__ == '__main__':
    main()
