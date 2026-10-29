"""Compare actual RTL frames with retained pre-optimization RGB references."""
from pathlib import Path
from PIL import Image,ImageChops
import json,hashlib
root=Path(__file__).resolve().parents[2]
records=[]
for i in range(5):
    actual_path=root/f'.agent/build/sim/osd/frame{i}.ppm'
    reference_path=root/f'sim/osd/reference/frame{i}.png'
    actual=Image.open(actual_path).convert('RGB')
    reference=Image.open(reference_path).convert('RGB')
    assert actual.size==reference.size==(1280,720)
    difference=ImageChops.difference(actual,reference)
    assert difference.getbbox() is None,(i,difference.getbbox())
    records.append({'frame':i,'rgb_sha256':hashlib.sha256(actual.tobytes()).hexdigest(),'exact_pixels':1280*720})
result={'status':'passed','exact_rgb_pixels':4608000,'frames':records}
(root/'.agent/build/sim/osd/equivalence.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PASS optimized OSD: all 4608000 RGB pixels exact with retained reference')
