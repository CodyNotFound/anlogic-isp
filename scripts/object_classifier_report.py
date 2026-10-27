"""Archive arithmetic and standalone FPGA evidence. No trained recognition claim."""
from pathlib import Path
import csv
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/object_classifier'


def area(path):
    txt=path.read_text()
    return {name:int(re.search(r'(?m)^[ \t]*#'+pattern+r'\s+(\d+)',txt)[1]) for name,pattern in
            [('slices',r'slice\*?'),('lut6','lut6'),('ff','reg'),('eram','eram'),('dsp','dsp')]}


def main():
    cases=[]
    for name in ['arithmetic','ties','negative','wide_margin','full_range']:
        log=(OUT/(name+'_modelsim.log')).read_text()
        if 'PASS ALL OBJECT' not in log or re.search(r'FAIL|\*\* (Error|Fatal)',log):raise ValueError(f'Unpassed RTL: {name}')
        rows=list(csv.DictReader((OUT/(name+'_rtl.csv')).open()))
        ref=json.loads((ROOT/'sim/object_classifier/selftest'/name/'reference.json').read_text())
        if len(rows)!=len(ref):raise ValueError('Incomplete RTL results')
        for actual,expected in zip(rows,ref):
            for key in ['class_id','rejected','margin']:
                if int(actual[key])!=int(expected[key]):raise ValueError(f'Prediction mismatch {name} {key}')
            for i,score in enumerate(expected['logits']):
                if int(actual[f'logit{i}'])!=score:raise ValueError('Logit mismatch')
            if int(actual['macs'])!=201600:raise ValueError('MAC count mismatch')
            cases.append(dict(model=name,**actual))
    probe=ROOT/'td_project/object_classifier_probe_r2'
    if not (probe/'.opt_route.end.f').exists():raise ValueError('Standalone place/route incomplete')
    for entry in json.loads((probe/'source_sha256.json').read_text(encoding='utf-8-sig')):
        if hashlib.sha256(Path(entry['Path']).read_bytes()).hexdigest().lower()!=entry['Hash'].lower():
            raise ValueError(f'Probe source changed: {entry["Path"]}')
    t=(probe/'object_classifier_probe_phy.ts').read_text()
    timing={k:float(re.search(k+r':\s*([-0-9.]+)ns',t)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
    summary=dict(model_contract_version=1,current_weights='arithmetic_selftest_NOT_TRAINED',
                 recognition_evaluated=False,trained_model_ready=False,
                 rtl_vectors_passed=len(cases),pooled_values_checked=len(cases)*1800,
                 macs_per_ROI=201600,cycles_per_ROI=int(cases[0]['cycles']),
                 estimated_ROI_ms_at_74_25MHz=round(int(cases[0]['cycles'])/74250,4),
                 standalone_routed_area=area(probe/'object_classifier_probe_phy.area'),
                 standalone_routed_timing=timing,standalone_internal_timing_pass=all(v>=0 for v in timing.values()),
                 camera_integrated=False,ROI_crop_resize_implemented=False,full_frame_detection=False,
                 main_project_integrated=False,board_tested=False)
    (OUT/'completion.json').write_text(json.dumps(summary,indent=2))
    (OUT/'integer_results.json').write_text(json.dumps(cases,indent=2))
    for name in ['object_classifier_probe_gate.area','object_classifier_probe_phy.area',
                 'object_classifier_probe_phy.ts','object_classifier_probe_pr.timing',
                 'object_classifier_probe_exception.timing','classifier.sdc','source_sha256.json']:
        (OUT/name).write_bytes((probe/name).read_bytes())
    manifest={}
    for folder in ['rtl/analytics/object_classifier','sim/object_classifier','scripts']:
        for p in (ROOT/folder).glob('*'):
            if p.is_file() and (folder!='scripts' or 'object_classifier' in p.name):
                manifest[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
    (OUT/'verified_sources.json').write_text(json.dumps(manifest,indent=2))
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
