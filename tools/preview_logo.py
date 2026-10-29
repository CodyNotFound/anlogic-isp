"""Render the shipped indexed logo without modifying any FPGA input."""
from pathlib import Path
import argparse
from PIL import Image

root = Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--out', type=Path, default=root / 'build/logo.png')
args = ap.parse_args()
indices = [int(v, 16) for v in (root / 'assets/rom/logo_idx.hex').read_text().split()]
palette = [int(v, 16) for v in (root / 'assets/rom/logo_pal.hex').read_text().split()]
assert len(indices) >= 146 * 94 and len(palette) == 256
im = Image.new('RGBA', (146, 94))
im.putdata([((palette[i] >> 16) & 255, (palette[i] >> 8) & 255, palette[i] & 255, 255 if i else 0) for i in indices[:146 * 94]])
args.out.parent.mkdir(parents=True, exist_ok=True)
im.save(args.out)
print(args.out)
