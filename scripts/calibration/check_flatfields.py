"""Measure fixed hardware LSC on neutral captures; does not fit or update LUTs."""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def gains(grid, phase, row, col):
    y, x = np.mgrid[row:720:2, col:1280:2]
    gy, gx = y//60, x//80
    fy, fx = (y%60)*256//60, (x%80)*256//80
    a, b = grid[gy,gx,phase], grid[gy,gx+1,phase]
    c, d = grid[gy+1,gx,phase], grid[gy+1,gx+1,phase]
    left = (a*(256-fy)+c*fy+128)//256
    right = (b*(256-fy)+d*fy+128)//256
    return (left*(256-fx)+right*fx+128)//256


def ratios(planes):
    # Robust phase medians in equal-sized blocks, excluding only boundary for measurement.
    med = np.stack([np.array([[np.median(p[y:y+30,x:x+40])
                              for x in range(40,600,40)] for y in range(30,330,30)])
                    for p in planes], axis=-1)
    green = (med[:,:,0]+med[:,:,3])/2
    result = {}
    for name, phase in [('R/G',1),('B/G',2)]:
        r = med[:,:,phase]/np.maximum(green,1)
        normalized = r/np.median(r)
        result[name] = {'spatial_p95_abs_percent':float(np.percentile(abs(normalized-1),95)*100),
                        'left_center_right_normalized':[float(np.median(normalized[:,s]))
                                                       for s in (slice(0,3),slice(5,9),slice(-3,None))]}
    return result


def main():
    ap=argparse.ArgumentParser();ap.add_argument('raw',type=Path,nargs='+');ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();grid=np.load(ROOT/'assets/calibration/base_grid_q10.npy').astype('int64')
    phase_coords=[(0,1),(1,1),(0,0),(1,0)];reports=[]
    for path in args.raw:
        raw=np.load(path);assert raw.shape==(720,1280) and raw.dtype==np.uint16 and raw.max()<=1023
        before=[np.maximum(raw[r::2,c::2].astype('int64')-67,0) for r,c in phase_coords]
        after=[np.minimum((p*gains(grid,i,r,c)+512)//1024,1023)
               for i,(p,(r,c)) in enumerate(zip(before,phase_coords))]
        reports.append({'file':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                        'raw_saturated_fraction':float((raw==1023).mean()),
                        'before_lsc':ratios(before),'after_fixed_integer_lsc':ratios(after)})
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps({'assumption':'neutral field; global WB normalized out; not independent validation because these captures contributed to calibration',
                                  'reports':reports},indent=2)+'\n',encoding='utf-8')
    print(args.out)


if __name__=='__main__':main()
