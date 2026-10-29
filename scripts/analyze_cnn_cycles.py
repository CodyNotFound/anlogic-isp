"""Attribute a verified full-network RTL run to its actual program operations."""
import argparse, hashlib, json, re
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--program", type=Path, default=Path("rtl/analytics/face_cnn/program.hex"))
parser.add_argument("--log", type=Path, required=True)
parser.add_argument("--mhz", type=float, default=150)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
text = args.log.read_text(encoding="utf-8-sig", errors="replace")
if "all 55 operations" not in text or "Errors: 0, Warnings: 0" not in text:
    raise SystemExit("A complete zero-error full-network regression is required")
records = {int(a): int(b) for a, b in re.findall(r"PASS YuNet operation(\d+) exact_bytes\d+ cycles(\d+)", text)}
program = args.program.read_text().split()
if set(records) != set(range(len(program))):
    raise SystemExit("Missing or mismatched per-operation cycle records")
groups = defaultdict(lambda: dict(cycles=0, scheduled_macs=0, layers=0))
rows = []
previous = 0
for index, word in enumerate(program):
    instruction = int(word, 16)
    def field(bit, size):
        return (instruction >> bit) & ((1 << size) - 1)
    opcode = field(0, 4)
    width, height = field(71, 8), field(79, 8)
    ci, co = field(87, 7), field(94, 7)
    kernel = 3 if field(101, 1) else 1
    depthwise = field(104, 1)
    kind = ("Depthwise" if depthwise else "Conv%dx%d" % (kernel, kernel)) if opcode == 1 else {2: "MaxPool", 3: "Resize", 4: "Add"}[opcode]
    cycles = records[index] - previous
    previous = records[index]
    macs = width * height * co * (1 if depthwise else ci) * kernel * kernel if opcode == 1 else 0
    rows.append(dict(index=index, kind=kind, width=width, height=height, ci=ci, co=co, cycles=cycles, scheduled_macs=macs))
    groups[kind]["cycles"] += cycles
    groups[kind]["scheduled_macs"] += macs
    groups[kind]["layers"] += 1
for group in groups.values():
    group["compute_ms"] = group["cycles"] / (args.mhz * 1000)
    group["cycle_percent"] = group["cycles"] * 100 / previous
result = dict(core_mhz=args.mhz, total_cycles=previous, compute_ms=previous / (args.mhz * 1000), scheduled_macs=sum(row["scheduled_macs"] for row in rows), groups=dict(groups), layers=rows,
              program_sha256=hashlib.sha256(args.program.read_bytes()).hexdigest(), log_sha256=hashlib.sha256(args.log.read_bytes()).hexdigest())
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: value for key, value in result.items() if key != "layers"}, indent=2))
