"""Write a trained torch checkpoint back into the original ONNX graph.

The graph topology (node names, ops, shapes) is untouched; only float32
initializer tensors are replaced, so every downstream consumer — this repo's
quantizer, the FPGA scheduler, the RTL testbench — sees the same structure it
was validated against.
"""
import argparse
from pathlib import Path

import torch

from yunet_torch import YuNetN, export_onnx_weights, ONNX_PATH, dec


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--checkpoint', type=Path, required=True, help='best_weights.pt from train.py')
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--src', type=Path, default=ONNX_PATH)
    args = ap.parse_args()

    blob = torch.load(args.checkpoint, map_location='cpu', weights_only=True)
    model = YuNetN()
    for k, v in blob.items():
        model.p[k] = torch.nn.Parameter(v.float())
    missing = model.expected_conv_params() - set(model.p.keys())
    if missing:
        raise KeyError(f'checkpoint missing tensors: {sorted(missing)[:5]}')
    export_onnx_weights(model, src=args.src, dst=args.output)
    print(f'wrote {args.output} ({args.output.stat().st_size} bytes) '
          f'from {args.checkpoint} with {len(blob)} tensors')


if __name__ == '__main__':
    main()
