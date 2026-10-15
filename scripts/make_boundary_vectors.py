"""Independent BGGR mirror101 golden vectors for the real demosaic RTL."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
sim = root / 'sim'
w, h = 1280, 6

def sample(x, y):
    # Include row gradients, chunk boundaries and a sharp right-edge stripe.
    r = 140 + 20*y + 4*(x//32) + (48 if x >= 1200 else 0)
    g = 280 + 12*y + 4*(x//64)
    b = 80 + 16*y + 4*(x//48)
    return r if y % 2 and x % 2 else b if not y % 2 and not x % 2 else g

raw = [[sample(x, y) for x in range(w)] for y in range(h)]

def mirror(v, n):
    return -v if v < 0 else 2*n-2-v if v >= n else v

def p(x, y):
    return raw[mirror(y, h)][mirror(x, w)] >> 2

def rgb(x, y):
    c = p(x, y)
    horizontal = (p(x-1, y) + p(x+1, y)) // 2
    vertical = (p(x, y-1) + p(x, y+1)) // 2
    cross = (p(x-1, y) + p(x+1, y) + p(x, y-1) + p(x, y+1)) // 4
    diagonal = sum(p(x+dx, y+dy) for dx in (-1, 1) for dy in (-1, 1)) // 4
    if y % 2 and x % 2:
        return c, cross, diagonal
    if not y % 2 and not x % 2:
        return diagonal, cross, c
    return (horizontal, c, vertical) if y % 2 else (vertical, c, horizontal)

words = [sum(raw[y][x+k] << (10*k) for k in range(4)) for y in range(h) for x in range(0, w, 4)]
expected = [rgb(x, y) for y in range(h) for x in range(w)]
(sim/'boundary_raw.hex').write_text(''.join(f'{v:010x}\n' for v in words), encoding='ascii')
(sim/'boundary_rgb.hex').write_text(''.join(f'{r:02x}{g:02x}{b:02x}\n' for r,g,b in expected), encoding='ascii')
# Check the resource-saving arithmetic over the entire hardware count range.
for count in range(1 << 22):
    assert (count << 6) + (count << 4) == count*80
    assert (count << 7) + (count << 5) + (count << 4) == count*176
for count in range(1 << 21):
    assert ((count << 8) + (count << 5) + (count << 1) + count) & ((1 << 30)-1) == (count*291) & ((1 << 30)-1)
report = dict(raw_words=len(words), golden_pixels=len(expected), geometry=[h,w],
              padding='mirror101', raw_max=max(map(max,raw)),
              arithmetic_count_bits_checked=[22,21], status='passed')
(root/'doc/compile/v9_vector_generation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
