"""Read-only workload audit; channel caps are estimates, not deployable models.
Run: python sim/face_motion/audit_face_program.py
Shape changes still require training, head-preserving graph validation, memory
rescheduling, quantization/export and RTL equivalence. MAC counts are not cycles.
"""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def audit(program):
    rows = []
    words = program.read_text().split()
    for i, word in enumerate(words):
        v = int(word, 16)
        def field(lo, bits):
            return (v >> lo) & ((1 << bits) - 1)
        if field(0, 4) != 1:
            continue
        rows.append(dict(index=i, ow=field(71,8), oh=field(79,8),
                         ci=field(87,7), co=field(94,7),
                         kernel=9 if field(101,1) else 1,
                         depthwise=bool(field(104,1))))
    def mac(row, cap):
        return (row['ow'] * row['oh'] * min(row['co'],cap) * row['kernel'] *
                (1 if row['depthwise'] else min(row['ci'],cap)))
    totals = {str(cap):sum(mac(row,cap) for row in rows) for cap in (64,32,16)}
    return dict(operations=len(words), convolution_mac_by_channel_cap=totals,
                note='Hypothetical graph-preserving channel reductions; not measured latency or accuracy.',
                top_layers=sorted([dict(r,mac=mac(r,64)) for r in rows],key=lambda r:-r['mac'])[:8])

if __name__ == '__main__':
    print(json.dumps(audit(ROOT/'rtl/analytics/face_cnn/program.hex'),indent=2))
