"""Validate measured RTL evidence; render actual pixels/coordinates and metrics."""
from pathlib import Path
import argparse,csv,hashlib,json,re,shutil
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from vision_tasks_reference import ROOT,BASE,OUT,luma


def log_pass(path,marker):
    s=path.read_text()
    if marker not in s or re.search(r'FAIL|\*\* (Error|Fatal)',s):raise ValueError(f'Incomplete/failed test: {path}')


def local_rms(gray):
    h,w=gray.shape
    a=gray[:h//16*16,:w//16*16].reshape(h//16,16,w//16,16).astype(float)
    return float(a.std((1,3)).mean())


def main():
    p=argparse.ArgumentParser();p.add_argument('--variant',default='r9');p.add_argument('--run',default='colorshading_runs_20261020_v34_tasks_r9');p.add_argument('--allow-pending-suite',action='store_true');args=p.parse_args()
    reference=json.loads((OUT/'reference.json').read_text())
    for test in ['helpers','sampler','tracker','region','region_overflow','clahe','demo_cdc','legacy_fixes','hud','gaussian','task_osd']:
        top='region' if test=='region_overflow' else test
        log_pass(OUT/f'{test}_{args.variant}.log',f'PASS tb_vision_{top}')
    suite=OUT/f'task_suite_{args.variant}.log'
    if not suite.exists():suite=OUT/f'suite_{args.variant}.log'
    suite_done=False
    if suite.exists() and 'PASS tb_vision_task_suite:' in suite.read_text():log_pass(suite,'PASS tb_vision_task_suite:');suite_done=True
    if not suite_done and not args.allow_pending_suite:raise ValueError('Native task integration incomplete')
    log_pass(OUT/f'face_pipeline_{args.variant}_console.log','PASS tb_face_pipeline:')
    log_pass(OUT/f'isp_cdc_regression_{args.variant}.log','PASS tb_isp_frame_preamble')
    for test in ['tb_ref_osd_mixer','tb_pixel_algorithm_ref_modes','tb_mode_ctrl_ref_modes']:
        log_pass(ROOT/'sim'/f'{test}.log',f'PASS {test}')
    records={}
    for kind in ['tracker','region']:
        rows=list(csv.DictReader((OUT/f'{kind}_rtl.csv').open()))
        if len(rows)!=len(reference[kind]):raise ValueError(f'{kind}: incomplete CSV')
        records[kind]=[]
        for row,expected in zip(rows,reference[kind]):
            actual={k:(v if k=='name' else int(v)) for k,v in row.items()}
            keys=['name','found']
            if kind=='tracker':
                keys+=['result','x','y']
                if expected['result']:keys+=['best','second','quality']
            else:
                keys+=['calibrated','overflow','area']
                if expected['found']:keys+=['x','y','w','h','cx','cy']
            for key in keys:
                if actual[key]!=expected[key]:raise ValueError(f'{kind} {actual["name"]}: {key} differs')
            actual['compute_ms_at_75MHz']=round(actual['cycles']/75000,4)
            records[kind].append(actual)
    overflow=list(csv.DictReader((OUT/'region_overflow_rtl.csv').open()))
    if len(overflow)!=2 or overflow[1]['overflow']!='1' or overflow[1]['found']!='0':raise ValueError('Region overflow fail-closed check failed')
    data=(OUT/'clahe_rtl.ppm').read_bytes();header=b'P6\n1280 720\n255\n'
    if not data.startswith(header) or len(data)!=len(header)+1280*720*3:raise ValueError('Incomplete actual RTL image')
    image=np.frombuffer(data[len(header):],np.uint8).reshape(720,1280,3)
    packed=np.array([int(s,16) for s in (BASE/'clahe_expected.hex').read_text().splitlines()],dtype=np.uint32).reshape(720,1280)
    expected=np.stack([(packed>>16)&255,(packed>>8)&255,packed&255],-1).astype(np.uint8)
    if not np.array_equal(image,expected):raise ValueError('Actual RTL pixel export differs from independent reference')
    original=np.asarray(Image.open(OUT/'clahe_input.png').convert('RGB'))
    Image.fromarray(image).save(OUT/'clahe_rtl.png')
    composed=OUT/'full_osd_rtl.ppm'
    if not composed.read_bytes().startswith(header) or composed.stat().st_size!=len(header)+1280*720*3:raise ValueError('Incomplete full application OSD export')
    Image.open(composed).save(OUT/'full_osd_rtl.png')
    for label in ['tracker','region']:
        ppm=OUT/f'{label}_hud_rtl.ppm'
        h=b'P6\n512 384\n255\n'
        if not ppm.read_bytes().startswith(h) or ppm.stat().st_size!=len(h)+512*384*3:raise ValueError('Incomplete actual HUD export')
        Image.open(ppm).save(OUT/f'{label}_hud_rtl.png')
    font=ImageFont.truetype('[LOCAL_PATH]',18)
    large=ImageFont.truetype('[LOCAL_PATH]',22)
    compare=Image.new('RGB',(1280,398),'#141b25')
    compare.paste(Image.fromarray(original).resize((640,360)),(0,0));compare.paste(Image.fromarray(image).resize((640,360)),(640,0))
    draw=ImageDraw.Draw(compare);draw.text((12,366),'Controlled uneven light: input',font=large,fill='white')
    draw.text((652,366),'Measured RTL: sampled CLAHE',font=large,fill='white');compare.save(OUT/'clahe_comparison.png')
    sheets={}
    chosen=dict(tracker=['track_seed','track_move','track_light','track_occluded','track_flat','track_ambiguous'],
                region=['region_components','region_move','region_edge','region_empty','region_neutral_pick','region_after_repick'])
    for kind,names in chosen.items():
        sheet=Image.new('RGB',(1536,860),'#141b25')
        for index,name in enumerate(names):
            item=next(row for row in records[kind] if row['name']==name)
            picture=Image.open(BASE/f'{name}.png').convert('RGB').resize((512,384),Image.Resampling.NEAREST)
            d=ImageDraw.Draw(picture)
            if item['found']:
                if kind=='tracker':x,y,w,h,cx,cy=item['x']-8,item['y']-8,16,16,item['x'],item['y']
                else:x,y,w,h,cx,cy=[item[k] for k in ['x','y','w','h','cx','cy']]
                d.rectangle((x*8,y*8,(x+w)*8-1,(y+h)*8-1),outline='#00ff40',width=3)
                d.line((cx*8-10,cy*8,cx*8+10,cy*8),fill='#ff4040',width=2)
                d.line((cx*8,cy*8-10,cx*8,cy*8+10),fill='#ff4040',width=2)
            x0=index%3*512;y0=index//3*430;sheet.paste(picture,(x0,y0));d=ImageDraw.Draw(sheet)
            d.text((x0+8,y0+388),f'{name} found={item["found"]}',font=font,fill='white')
            note=f'center=({item["x"]},{item["y"]}) Q={item["quality"]}' if kind=='tracker' else f'area={item["area"]} blocks; {item["area"]*64} source pixels'
            d.text((x0+8,y0+409),note,font=font,fill='#c4d3e3')
        name=f'{kind}_rtl_comparison.png';sheet.save(OUT/name);sheets[kind]=name
    before=luma(original);after=luma(image)
    unclipped=(image.min(2)>0)&(image.max(2)<255)
    a=image.astype(np.int16);b=original.astype(np.int16)
    if not np.array_equal((a[:,:,0]-a[:,:,1])[unclipped],(b[:,:,0]-b[:,:,1])[unclipped]):raise ValueError('Unexpected RGB-difference change')
    summary=dict(kind='three_embedded_vision_tasks',unit_functional_passed=True,native_task_suite_passed=suite_done,
        task_suite_video_pixels=2162688 if suite_done else 0,clahe_video_pixels_checked=921600,clahe_lut_values_checked=7680,
        core_records=records,region_queue_overflow_rejected=True,algorithms_original=False,board_tested=False,
        face_passthrough_video_pixels_checked=1843200,full_application_OSD_pixels_checked=921600,gaussian_nonuniform_pixels_checked=256,
        legacy_OSD_buttons_pixels_passed=True,ISP_preamble_regression_passed=True,
        gimbal_actuation_implemented=False,semantic_object_classification=False,face_identity_recognition=False,
        clahe_metrics=dict(input_dark_half_local_rms=local_rms(before[:,:640]),rtl_dark_half_local_rms=local_rms(after[:,:640]),
            input_saturated_fraction=float(np.mean((original==255).any(2))),rtl_saturated_fraction=float(np.mean((image==255).any(2)))),
        limitations=['Controlled synthetic motion/color and transformed photo fixtures are not field accuracy estimates.',
            'Frozen gradient tracking can fail under scale/rotation/deformation and must be explicitly reacquired.',
            'Color segmentation is scene-conditioned and cannot infer item categories.',
            'CLAHE statistics are subsampled with 32 bins and previous-frame mapping; noise/scene changes need camera tests.'])
    paths=list((ROOT/'rtl/analytics/vision_tasks').glob('*.v'))+[ROOT/'rtl/app/vision_pipeline.v',ROOT/'rtl/control/mode_ctrl.v',ROOT/'rtl/control/vision_demo_cdc.v',ROOT/'rtl/isp/pixel_algorithm.v',ROOT/'user_source/hdl_source/isp/isp_top.v',ROOT/'user_source/hdl_source/hdmi_mixer.v',ROOT/'rtl/config/vision_config.vh']
    hashes={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in paths}
    saved=OUT/f'functional_source_sha256_{args.variant}.json'
    if saved.exists() and json.loads(saved.read_text())!=hashes:raise ValueError('Functional RTL changed after evidence snapshot: rerun impacted tests and use a fresh evidence directory')
    saved.write_text(json.dumps(hashes,indent=2));summary['functional_RTL_files_checked']=len(hashes)
    run=ROOT/'td_project'/args.run;summary['build_run']=args.run
    if (run/'source_sha256.txt').exists():
        for line in (run/'source_sha256.txt').read_text().splitlines():
            digest,rel=line.split('  ',1)
            if hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=digest.lower():raise ValueError(f'Build inputs changed: {rel}')
        summary['build_source_files_checked']=len((run/'source_sha256.txt').read_text().splitlines())
    for sub,label in [('syn','gate'),('phy','phy')]:
        f=run/sub/f'camera_to_dsi_display_{label}.area'
        if f.exists():summary[f'{label}_area']={k:int(re.search(r'(?m)^\s*#'+pat+r'\s+(\d+)',f.read_text())[1]) for k,pat in [('slices','slice\\*?'),('lut6','lut6'),('eram','eram'),('dsp','dsp')]}
    timing=run/'phy/camera_to_dsi_display_phy.ts'
    if timing.exists():
        text=timing.read_text();summary['routed_timing']={k:float(re.search(k+r':\s*([-0-9.]+)ns',text)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
        summary['routed_timing_passed']=all(v>=0 for v in summary['routed_timing'].values())
        exception=(run/'phy/camera_to_dsi_display_exception.timing').read_text()
        bits=set()
        for block in exception.split('Slack'):
            target=re.search(r'End Point\s*:\s*([^\n]+)',block)
            if not target or '/u_demo_cdc/' not in target[1]:continue
            bit=re.search(r'/meta_reg\[(\d)\][^.]*\.(?:d|ima)\b',target[1])
            if not bit or '20.000' not in block:raise ValueError('CDC exception reached a later stage or lacks the delay bound')
            bits.add(int(bit[1]))
        if bits!={0,1,2,3}:raise ValueError('CDC constraint must cover exactly four first-stage D pins')
        phylog=(run/'phy/implementation.log').read_text()
        if 'USR-8159' in phylog or 'must match exactly four' in phylog:raise ValueError('Implementation has a failed SDC command')
        summary['CDC_first_stage_D_pins_verified']=4
    origin=run/'checkpoint_provenance.json'
    if origin.exists():summary['constraint_revision_provenance']=json.loads(origin.read_text())
    version=args.run.split('_20261020_',1)[-1];job=ROOT/f'doc/compile/{version}_job.json'
    if job.exists():summary['build_job']=json.loads(job.read_text(encoding='utf-8-sig'))
    bit=run/'phy/camera_to_dsi_display.bit'
    if bit.exists() and summary.get('build_job',{}).get('status')!='running':summary['bitstream']=dict(path=str(bit),bytes=bit.stat().st_size,sha256=hashlib.sha256(bit.read_bytes()).hexdigest())
    (OUT/'completion.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
