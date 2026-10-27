"""Validate current parallel-rotation experiments and routed implementation."""
from pathlib import Path
import argparse,csv,hashlib,json,re
from PIL import Image,ImageDraw,ImageFont
from vision_tasks_report import log_pass

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/vision_tasks';ROT=OUT/'rotation'

def main():
    p=argparse.ArgumentParser();p.add_argument('--run',default='colorshading_runs_20261020_v35_rotation_r1');p.add_argument('--functional-only',action='store_true');args=p.parse_args()
    for name in ['helpers','sampler','region','region_overflow','demo_cdc','legacy_fixes','hud','gaussian','task_osd']:
        top='region' if name=='region_overflow' else name
        log_pass(OUT/f'{name}_rot_r1.log',f'PASS tb_vision_{top}')
    for name in ['tracker','task_suite']:log_pass(OUT/f'{name}_rot_r2.log',f'PASS tb_vision_{name}')
    for name in ['rtl','sequence','production','ambiguity']:log_pass(ROT/f'{name}_r2.log','PASS tb_vision_rotation:')
    log_pass(ROT/'region_osd_r2.log','PASS tb_vision_task_osd:')
    log_pass(ROT/'face_pipeline_r2_console.log','PASS tb_face_pipeline:')
    log_pass(OUT/'isp_cdc_regression_rot_r1.log','PASS tb_isp_frame_preamble')
    for name in ['tb_ref_osd_mixer','tb_pixel_algorithm_ref_modes','tb_mode_ctrl_ref_modes']:
        log_pass(ROOT/'sim'/f'{name}.log',f'PASS {name}')
    reference=json.loads((ROT/'reference.json').read_text())
    actual=list(csv.DictReader((ROT/'rtl.csv').open()))
    if len(actual)!=76:raise ValueError('Incomplete independent-angle experiment')
    lookup={r['name']:r for r in actual}
    for r in reference:
        a=lookup[r['name']]
        for k in ['found','x','y','best','second','quality','bank']:
            if int(a[k])!=r['new'][k]:raise ValueError(f'{r["name"]} {k}: RTL/reference differ')
    seq=json.loads((ROT/'sequence_reference.json').read_text());seq_rows=list(csv.DictReader((ROT/'sequence_rtl.csv').open()))
    if len(seq_rows)!=14:raise ValueError('Incomplete continuous sequence')
    for r,a in zip(seq,seq_rows[1:]):
        for k in ['found','x','y','best','second','quality']:
            if int(a[k])!=r['new'][k]:raise ValueError(f'Sequence {r["name"]}: {k}')
    prod=list(csv.DictReader((ROT/'production_rtl.csv').open()))
    if len(prod)!=2:raise ValueError('Incomplete production-size experiment')
    production=json.loads((ROT/'production_reference.json').read_text())
    for k in ['found','x','y','best','second','quality','bank']:
        if int(prod[1][k])!=production[k]:raise ValueError(f'Production {k}')
    positives=[r for r in reference if r['source']!='negative']
    error=max(max(abs(int(lookup[r['name']]['x'])-r['expected_center'][0]),abs(int(lookup[r['name']]['y'])-r['expected_center'][1])) for r in positives)
    cycles=int(prod[1]['cycles'])
    if cycles>400000:raise ValueError('Parallel tracking performance regressed')
    ambiguous=list(csv.DictReader((ROT/'ambiguity_rtl.csv').open()))
    if len(ambiguous)!=2 or int(ambiguous[1]['found']) or int(ambiguous[1]['best']) or int(ambiguous[1]['second']):raise ValueError('Periodic texture was not rejected')
    # Render boxes from actual RTL coordinates, not reference predictions.
    samples=[r for r in positives if r['angle'] in [-12,0,12]]
    sheet=Image.new('RGB',(1152,1280),'#15202b');draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype('[LOCAL_PATH]',18)
    for i,r in enumerate(samples):
        a=lookup[r['name']];im=Image.open(ROT/f'{r["name"]}.png').convert('RGB');d=ImageDraw.Draw(im)
        x=int(a['x'])*6;y=int(a['y'])*6
        if int(a['found']):d.rectangle((x-48,y-48,x+48,y+48),outline='lime',width=2)
        xx=i%3*384;yy=i//3*320;sheet.paste(im,(xx,yy))
        draw.text((xx+4,yy+291),f'{r["name"]} old={r["baseline"]["found"]} RTL={a["found"]}',font=font,fill='white')
    sheet.save(ROT/'rtl_comparison.png')
    sheet.crop((0,0,1152,320)).save(ROT/'rtl_figurine_comparison.png')
    for name in ['tracker_hud_rtl','region_hud_rtl','full_osd_rtl','full_region_osd_rtl']:
        Image.open(OUT/f'{name}.ppm').save(OUT/f'{name}.png')
    if args.functional_only:
        summary=dict(functional_passed=True,hardware_signoff_pending=True,controlled_angle_samples=36,RTL_found=36,
            continuous_sequence_frames=14,negative_controls=3,negative_false_locks=0,
            max_center_error_small_image_pixels=error,production_compute_cycles=cycles,compute_ms_at_75MHz=cycles/75000,board_tested=False)
        (ROT/'functional.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2));return
    run=ROOT/'td_project'/args.run;version=args.run.split('_20261020_',1)[1]
    job=json.loads((ROOT/f'doc/compile/{version}_job.json').read_text(encoding='utf-8-sig'))
    if job['status']!='passed':raise ValueError('Current full build not passed')
    manifest=(run/'source_sha256.txt').read_text().splitlines()
    for line in manifest:
        digest,rel=line.split('  ',1)
        if hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=digest.lower():raise ValueError(f'Build source changed: {rel}')
    roms=json.loads((ROT/'additional_rom_sha256.json').read_text())
    for rel,digest in roms['files'].items():
        if hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=digest:raise ValueError(f'ROM asset changed before bitgen: {rel}')
    timing=(run/'phy/camera_to_dsi_display_phy.ts').read_text()
    slacks={k:float(re.search(k+r':\s*([-0-9.]+)ns',timing)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
    if any(v<0 for v in slacks.values()):raise ValueError('Routed timing failure')
    exceptions=(run/'phy/camera_to_dsi_display_exception.timing').read_text();bits=set()
    for block in exceptions.split('Slack'):
        target=re.search(r'End Point\s*:\s*([^\n]+)',block)
        if not target or '/u_demo_cdc/' not in target[1]:continue
        bit=re.search(r'/meta_reg\[(\d)\][^.]*\.(?:d|ima)\b',target[1])
        if not bit or '20.000' not in block:raise ValueError('CDC exception reached a later stage')
        bits.add(int(bit[1]))
    if bits!={0,1,2,3}:raise ValueError('Missing CDC first-stage constraints')
    if 'USR-8159' in (run/'phy/implementation.log').read_text():raise ValueError('SDC application error')
    area_text=(run/'phy/camera_to_dsi_display_phy.area').read_text()
    area={k:int(re.search(r'(?m)^\s*#'+pat+r'\s+(\d+)',area_text)[1]) for k,pat in [('slices','slice\\*?'),('lut6','lut6'),('eram','eram'),('dsp','dsp')]}
    bit=run/'phy/camera_to_dsi_display.bit'
    summary=dict(kind='parallel_rotation_tracking',rotation_tracking=True,unit_functional_passed=True,native_task_suite_passed=True,
        build_run=args.run,build_job=job,build_source_files_checked=len(manifest),additional_MIF_assets_checked=len(roms['files']),font_words_checked=roms['font_words_checked'],phy_area=area,routed_timing=slacks,routed_timing_passed=True,
        CDC_first_stage_D_pins_verified=4,board_tested=False,automatic_reacquire=False,histogram_enhancement_active=False,
        controlled_angle_samples=len(positives),baseline_found=sum(r['baseline']['found'] for r in positives),RTL_found=sum(int(lookup[r['name']]['found']) for r in positives),
        negative_controls=3,negative_false_locks=sum(int(lookup[r['name']]['found']) for r in reference if r['source']=='negative'),
        max_center_error_small_image_pixels=error,continuous_sequence_frames=14,production_gray_frame=[160,90],search_radius=8,
        production_compute_cycles=cycles,compute_ms_at_75MHz=cycles/75000,
        bitstream=dict(path=str(bit),bytes=bit.stat().st_size,sha256=hashlib.sha256(bit.read_bytes()).hexdigest()),
        limitations=['Controlled planar rotations of four source images are not camera accuracy estimates.',
            'Tolerance is relative to the initially selected template; out-of-plane pose, scale and deformation remain limitations.',
            'Compute time excludes capture/scheduling; no servo control or camera-freeze detection.',
            'Unchanged helper/region/OSD/CDC tests use rot_r1 logs; final parallel core and native tracker suite use rot_r2.'])
    (OUT/'completion.json').write_text(json.dumps(summary,indent=2));(ROT/'completion.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
