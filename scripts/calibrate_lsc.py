"""Build a 17x13 BGGR spatial LSC map from a verified neutral RAW10 frame.

Usage: calibrate_lsc.py flatfield.npy spatial_grid_float.npy
Input is an unprocessed 720x1280 uint16 array, range 0..1023. A photograph of
an HDMI display cannot calibrate sensor shading and is deliberately rejected.
Output matches export_calibration.py; no RTL is overwritten automatically.
"""
from pathlib import Path
import argparse
import numpy as np

def calibrate(raw, black=67):
    if raw.shape != (720,1280) or raw.dtype != np.uint16 or raw.max()>1023:
        raise ValueError('Expected verified 720x1280 uint16 RAW10 (0..1023)')
    if float((raw>=1020).mean())>.01:
        raise ValueError('Flatfield clips highlights; reduce exposure and recapture')
    grid=np.empty((13,17,4),dtype=np.float64)
    for phase,(row,col) in enumerate(((0,1),(1,1),(0,0),(1,0))):
        plane=np.maximum(raw[row::2,col::2].astype(np.float64)-black,0)
        reference=float(np.median(plane[120:240,240:400]))
        if reference<16:raise ValueError('Flatfield too dark; need signal above black level')
        for gy,y in enumerate(np.linspace(0,359,13)):
            for gx,x in enumerate(np.linspace(0,639,17)):
                iy,ix=int(round(y)),int(round(x))
                sample=float(np.median(plane[max(0,iy-15):min(360,iy+16),max(0,ix-20):min(640,ix+21)]))
                if sample<8:raise ValueError(f'Dark/occluded grid node {gy},{gx},phase {phase}')
                grid[gy,gx,phase]=reference/sample
    if not np.isfinite(grid).all() or grid.min()<=0 or grid.max()>4095/1024:
        raise ValueError('Required spatial gain exceeds hardware Q2.10 range')
    return grid

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('raw',type=Path);ap.add_argument('out',type=Path)
    ap.add_argument('--black',type=int,default=67)
    args=ap.parse_args()
    if args.raw.suffix.lower()!='.npy' or args.out.suffix.lower()!='.npy':
        ap.error('Input and output must be .npy; processed photographs are not RAW calibration')
    if args.out.exists():ap.error('Output exists; choose a new path and review before replacing calibration')
    if not 0<=args.black<1023:ap.error('Invalid black level')
    grid=calibrate(np.load(args.raw,allow_pickle=False),args.black)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    np.save(args.out,grid)
    print(f'Wrote {args.out}: shape={grid.shape}, gain={grid.min():.4f}..{grid.max():.4f}')
    print('Review neutral-field measurements; export_calibration.py consumes the indoor/daylight maps.')
if __name__=='__main__':main()
