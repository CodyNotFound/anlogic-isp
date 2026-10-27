"""Join actual RTL logs, hand annotations and TD evidence; never equate PASS with recognition accuracy."""
from pathlib import Path
import csv
import json
import re
import hashlib
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/face_lbp'
# Manually reviewed coarse face rectangles in the 160x90 fixtures, x,y,w,h.
# These are evaluation annotations, never consumed by detector/model export.
TRUTH={
 'lena_full':(73,34,30,31), 'lena_dim':(73,34,30,31),
 'hopper_full':(66,17,32,32), 'messi_full':(66,23,12,14),
 'photo_left':(20,26,32,32), 'photo_right':(108,38,32,32),
 'figurine_human_model':(53,29,29,23), 'figurine_anime_model':(53,29,29,23),
}


def iou(box,truth):
    x,y,w=box;tx,ty,tw,th=truth
    area=max(0,min(x+w,tx+tw)-max(x,tx))*max(0,min(y+w,ty+th)-max(y,ty))
    return area/(w*w+tw*th-area) if w else 0


def main():
    ref=json.loads((OUT/'reference.json').read_text())
    rows=list(csv.DictReader((OUT/'rtl_results.csv').open()))
    assert len(rows)==len(ref['cases']), 'Incomplete RTL simulation'
    assert 'PASS ALL' in (OUT/'modelsim.log').read_text(), 'RTL suite did not pass'
    assert 'PASS protocol' in (OUT/'protocol.log').read_text(), 'Protocol suite did not pass'
    evaluated=[]
    for item,row in zip(ref['cases'],rows):
        assert row['name']==item['name'] and int(row['features'])==item['features']
        assert int(row['found'])==item['target']['found']
        for axis,v in zip(['x','y','size'],item['target']['box']): assert int(row[axis])==v
        box=[int(row[k]) for k in ['x','y','size']]
        found=bool(int(row['found']))
        score=iou(box,TRUTH[item['name']]) if item['name'] in TRUTH else None
        if item['name'].endswith('negative'):
            outcome='correct_reject' if not found else 'false_positive'
        elif item['name'] in TRUTH:
            outcome='localized' if found and score>=0.5 else ('mislocalized' if found else 'missed')
        else:
            outcome='missed' if not found else 'needs_annotation'
        evaluated.append(dict(**row,iou=None if score is None else round(score,3),outcome=outcome,
                              compute_ms_at_74_25MHz=round(int(row['cycles'])/74250,2)))
    manifest={}
    for folder in ['rtl/analytics/face_lbp','sim/face_lbp']:
        for p in (ROOT/folder).glob('*'):
            if p.is_file(): manifest[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
    (OUT/'verified_sources.json').write_text(json.dumps(manifest,indent=2))
    (OUT/'evaluation.json').write_text(json.dumps(evaluated,indent=2))
    # Static engineering evidence; green is the actual RTL-selected target,
    # orange is independent human annotation. Images derive from the fixtures.
    cols=3;cellw=480;cellh=310
    sheet=Image.new('RGB',(cols*cellw,((len(rows)+cols-1)//cols)*cellh),'#171c25')
    for idx,(item,e) in enumerate(zip(ref['cases'],evaluated)):
        im=Image.open(OUT/(item['name']+'.png')).resize((480,270))
        d=ImageDraw.Draw(im)
        if item['name'] in TRUTH:
            x,y,w,h=TRUTH[item['name']]
            d.rectangle((x*3,y*3,(x+w)*3,(y+h)*3),outline='orange',width=2)
        x0=(idx%cols)*cellw;y0=(idx//cols)*cellh
        sheet.paste(im,(x0,y0))
        d=ImageDraw.Draw(sheet)
        d.text((x0+8,y0+273),f"{item['name']}: {e['outcome']}",fill='white')
        d.text((x0+8,y0+291),f"votes={e['votes']}  {e['compute_ms_at_74_25MHz']}ms @74.25MHz (projection)",fill='#b9c6d8')
    sheet.save(OUT/'contact_sheet.png')
    lines=['| 样本 | RTL目标框 x,y,w | 票数 | 独立评估 | IoU | 周期 | 74.25MHz计算时间估算 |',
           '|---|---|---:|---|---:|---:|---:|']
    for e in evaluated:
        lines.append(f"| {e['name']} | {e['x']},{e['y']},{e['size']} | {e['votes']} | {e['outcome']} | {e['iou']} | {e['cycles']} | {e['compute_ms_at_74_25MHz']}ms |")
    (OUT/'results_table.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(lines))


if __name__=='__main__': main()
