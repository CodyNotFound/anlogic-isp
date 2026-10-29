"""Prove signed depthwise accumulator bounds for the packed production graph."""
import argparse
import hashlib
import json
from pathlib import Path


def prove(root, bits):
    rom = root / 'rtl/analytics/face_cnn'
    names = ['program.hex', 'bias.hex', 'shift.hex'] + [f'weights{i}.hex' for i in range(4)]
    values = {name: [int(v, 16) for v in (rom / name).read_text().split()] for name in names}
    banks = [values[f'weights{i}.hex'] for i in range(4)]
    layers = []
    for index, instruction in enumerate(values['program.hex']):
        if instruction & 15 != 1 or not (instruction >> 104 & 1):
            continue
        if instruction >> 147 & 1:
            raise ValueError('Unsigned depthwise input is outside this proof contract')
        channels = instruction >> 94 & 127
        weight_base = instruction >> 106 & 65535
        bias_base = instruction >> 122 & 2047
        taps = 9 if instruction >> 101 & 1 else 1
        low, high = 1 << 63, -(1 << 63)
        for channel in range(channels):
            bias = values['bias.hex'][bias_base + channel]
            bias = bias - (1 << 32) if bias & (1 << 31) else bias
            shift = values['shift.hex'][bias_base + channel]
            if not 0 <= shift <= 31:
                raise ValueError('Depthwise shift outside 0..31')
            minimum = maximum = bias
            # Include the initial bias and EVERY prefix, not only the final sum.
            low, high = min(low, minimum), max(high, maximum)
            for tap in range(taps):
                address = weight_base + tap * channels + channel
                weight = banks[address % 4][address // 4]
                weight = weight - 256 if weight > 127 else weight
                minimum += min(-128 * weight, 127 * weight)
                maximum += max(-128 * weight, 127 * weight)
                low, high = min(low, minimum), max(high, maximum)
        needed = next(n for n in range(2, 65) if -(1 << (n-1)) <= low and high < (1 << (n-1)))
        if needed > bits:
            raise ValueError(f'Layer {index} needs {needed} bits, proposed {bits}')
        layers.append(dict(operation=index, channels=channels, minimum=low, maximum=high, required_bits=needed))
    if not layers:
        raise ValueError('No depthwise operations found')
    return dict(status='passed', accumulator_bits=bits, input_domain=[-128, 127],
                weight_layout='tap-major depthwise, four interleaved ROM banks', layers=layers,
                sha256={name: hashlib.sha256((rom / name).read_bytes()).hexdigest() for name in names})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--bits', type=int, default=18)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = prove(args.root, args.bits)
    rendered = json.dumps(result, indent=2)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rendered + chr(10), encoding='utf-8')
    print(json.dumps(dict(status=result['status'], operations=len(result['layers']), accumulator_bits=args.bits)))
