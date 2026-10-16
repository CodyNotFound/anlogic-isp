"""Summarize actual TD reports, with source consistency and scope attached."""
from pathlib import Path
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/face_lbp'


def timing(p):
    text=p.read_text()
    keys=['SWNS','STNS','HWNS','HTNS']
    return {k:float(re.search(k+r':\s*([-0-9.]+)ns',text)[1]) for k in keys}


def area(p):
    text=p.read_text()
    return {name:int(re.search(r'(?m)^[ \t]*#'+pattern+r'\s+(\d+)',text)[1]) for name,pattern in
            [('slices',r'slice\*?'),('lut6','lut6'),('ff',r'reg'),('eram','eram'),('dsp','dsp')]}


def main():
    probe=ROOT/'td_project/face_lbp_probe_r5'
    baseline=ROOT/'td_project/colorshading_runs_20261019_v31_face_feasibility_baseline/syn'
    assert (probe/'.opt_route.end.f').exists(), 'Standalone route incomplete'
    assert (baseline/'.opt_gate.end.f').exists(), 'Active baseline synthesis incomplete'
    hashes=json.loads((probe/'source_sha256.json').read_text(encoding='utf-8-sig'))
    for entry in hashes:
        assert hashlib.sha256(Path(entry['Path']).read_bytes()).hexdigest().lower()==entry['Hash'].lower(), entry['Path']
    result=dict(scope='standalone internal timing probe; not camera integration or board signoff',
                target='PH1P35MDG324/-3',clock_period_ns=13.468,
                standalone_gate=area(probe/'face_lbp_probe_gate.area'),
                standalone_routed=area(probe/'face_lbp_probe_phy.area'),
                standalone_timing=timing(probe/'face_lbp_probe_phy.ts'),
                active_baseline_gate=area(baseline/'camera_to_dsi_display_gate.area'),
                active_baseline_gate_timing=timing(baseline/'camera_to_dsi_display_gate.ts'),
                main_project_integration=False,board_verified=False,bitstream_generated=False)
    result['standalone_internal_timing_pass']=all(v>=0 for v in result['standalone_timing'].values())
    (OUT/'hardware_summary.json').write_text(json.dumps(result,indent=2))
    # Keep small durable evidence beside recognition results. Full databases remain in TD runs.
    for p in [probe/'face_lbp_probe_gate.area',probe/'face_lbp_probe_phy.area',probe/'face_lbp_probe_phy.ts',
              probe/'face_lbp_probe_pr.timing',probe/'face_lbp_probe_exception.timing',
              probe/'source_sha256.json',probe/'face.sdc',baseline/'camera_to_dsi_display_gate.area',
              baseline/'camera_to_dsi_display_gate.ts']:
        (OUT/p.name).write_bytes(p.read_bytes())
    print(json.dumps(result,indent=2))


if __name__=='__main__': main()
