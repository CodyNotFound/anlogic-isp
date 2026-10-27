"""Validate scale/roll RTL evidence, render measured boxes, and archive build status."""
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/face_pose'
RUN='colorshading_runs_20261019_v33_face_pose_r3'
CASE_OUT=OUT/'r3'


def iou(box,gt):
    x,y,w=box;gx,gy,gw,gh=gt
    inter=max(0,min(x+w,gx+gw)-max(x,gx))*max(0,min(y+w,gy+gh)-max(y,gy))
    return inter/(w*w+gw*gh-inter) if w*w+gw*gh-inter else 0.


def area(path):
    text=path.read_text()
    return {name:int(re.search(r'(?m)^\s*#'+pattern+r'\s+(\d+)',text)[1]) for name,pattern in
            [('slices',r'slice\*?'),('lut6','lut6'),('eram','eram'),('dsp','dsp')]}


def main():
    reference=json.loads((OUT/'reference.json').read_text())
    evaluated=[]
    for case in reference['cases']:
        name=case['name'];log=(CASE_OUT/f'{name}_modelsim.log').read_text()
        if f'PASS tb_face_pose {name}' not in log or re.search(r'FAIL|\*\* (Error|Fatal)',log):raise ValueError(f'Incomplete/failed case: {name}')
        rows=list(csv.DictReader((CASE_OUT/f'{name}_rtl.csv').open()))
        if len(rows)!=1:raise ValueError('Incomplete result rows')
        actual={k:int(v) for k,v in rows[0].items() if k!='name'}
        expected=case['expected']
        for key,value in dict(found=int(expected['found']),x=expected['box'][0],y=expected['box'][1],size=expected['box'][2],
                              center_x=expected['center'][0],center_y=expected['center'][1],votes=expected['votes'],view=expected['view'],
                              features=case['total_features'],views=len(case['views'])).items():
            if actual[key]!=value:raise ValueError(f'{name} RTL differs from reference: {key}')
        gt=case['ground_truth'];new_box=[actual[k] for k in ['x','y','size']]
        old_iou=iou(case['old']['box'],gt) if gt else None
        new_iou=iou(new_box,gt) if gt else None
        if gt and (not actual['found'] or new_iou<.5):raise ValueError(f'{name}: a box is not a sufficiently localized face')
        if not gt and actual['found']:raise ValueError('False positive on negative control')
        evaluated.append(dict(name=name,**actual,old_found=case['old']['found'],old_iou=old_iou,
            new_iou=new_iou,ground_truth=gt,compute_ms_at_75MHz=round(actual['cycles']/75000,3)))
    for test in ['tb_face_position_overlay','tb_face_video_timeout','tb_face_video_result_ttl','tb_face_video_mode']:
        log=(CASE_OUT/'video'/f'{test}.log').read_text()
        if f'PASS {test}' not in log or re.search(r'FAIL|\*\* (Error|Fatal)',log):raise ValueError(f'Video integration test failed: {test}')
    pipeline=(CASE_OUT/'pipeline_sim_console.log').read_text()
    if 'PASS tb_face_pipeline' not in pipeline or re.search(r'FAIL|\*\* (Error|Fatal)',pipeline):raise ValueError('Application integration incomplete')
    legacy=(CASE_OUT/'legacy_anime_modelsim.log').read_text()
    if 'PASS ALL LBP RTL fixtures' not in legacy or re.search(r'FAIL|\*\* (Error|Fatal)',legacy):raise ValueError('Legacy dual-model compatibility failed')
    ppm=CASE_OUT/'video/lena_video_rtl.ppm'
    if len(ppm.read_bytes())!=len(b'P6\n1280 720\n255\n')+1280*720*3:raise ValueError('Incomplete native-video overlay')
    with Image.open(ppm) as image:image.save(CASE_OUT/'video/lena_video_rtl.png')
    font=ImageFont.truetype('[LOCAL_PATH]',18)
    sheet=Image.new('RGB',(3*640,2*416),'#141b25')
    for index,item in enumerate(evaluated):
        image=Image.open(ROOT/'sim/face_pose'/f"{item['name']}.png").convert('RGB').resize((640,360),Image.Resampling.NEAREST)
        draw=ImageDraw.Draw(image)
        if item['ground_truth']:
            x,y,w,h=item['ground_truth'];draw.rectangle((x*4,y*4,(x+w)*4,(y+h)*4),outline='orange',width=2)
        if item['found']:
            x,y,w=[item[k] for k in ['x','y','size']];cx,cy=item['center_x']*4,item['center_y']*4
            draw.rectangle((x*4,y*4,(x+w-1)*4,(y+w-1)*4),outline='#00ff40',width=2)
            draw.line((cx-12,cy,cx+12,cy),fill='#ff4040',width=2);draw.line((cx,cy-12,cx,cy+12),fill='#ff4040',width=2)
        x0=index%3*640;y0=index//3*416;sheet.paste(image,(x0,y0));draw=ImageDraw.Draw(sheet)
        draw.text((x0+8,y0+364),f"{item['name']}: old={int(item['old_found'])} new={item['found']}  view={item['view']}",fill='white',font=font)
        quality='negative control' if item['new_iou'] is None else f"IoU={item['new_iou']:.3f}"
        draw.text((x0+8,y0+388),f"{quality}  {item['compute_ms_at_75MHz']} ms (compute estimate)",fill='#c4d3e3',font=font)
    ImageDraw.Draw(sheet).text((1288,430),'Green: measured RTL box\nOrange: transformed coarse GT\n\nOne photo, controlled transforms.\nNot independent camera accuracy.',fill='white',font=font,spacing=10)
    sheet.save(OUT/'rtl_pose_comparison.png')
    run=ROOT/'td_project'/RUN
    sources={}
    for entry in (run/'source_sha256.txt').read_text().splitlines():
        digest,rel=entry.split('  ',1)
        actual=hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()
        if actual!=digest.lower():raise ValueError(f'Build source changed: {rel}')
        sources[rel]=actual
    (OUT/'source_sha256.json').write_text(json.dumps(sources,indent=2))
    job=json.loads((ROOT/'doc/compile/v33_face_pose_r3_job.json').read_text(encoding='utf-8-sig'))
    summary=dict(kind='scale_and_roll_control_experiment',scales=reference['scales'],angles=reference['angles'],cases=evaluated,
        rotated_pixels_checked=sum(c['views'] for c in evaluated)*14400,independent_accuracy_evaluation=False,
        native_RGB_video_integration_passed=True,application_video_pixels_checked=1843200,legacy_dual_model_smoke_passed=True,
        board_tested=False,gimbal_control_implemented=False,build_job=job,source_files_checked=len(sources),
        result_wall_clock_expiry_tested=True,result_TTL_cycles=75000000,
        limitations=['Tilt retries can take about five times as long as upright detection.',
            'Whole/partial face outside the image, optical defocus and motion blur are not solved by larger windows.',
            'Tested roll controls do not establish yaw/profile or arbitrary-angle performance.'])
    for stage,name in [('syn','gate'),('phy','phy')]:
        path=run/stage/f'camera_to_dsi_display_{name}.area'
        if path.exists():summary[f'{name}_area']=area(path)
    path=run/'phy/camera_to_dsi_display_phy.ts'
    if path.exists():
        txt=path.read_text();summary['routed_timing']={k:float(re.search(k+r':\s*([-0-9.]+)ns',txt)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
        summary['routed_timing_passed']=all(v>=0 for v in summary['routed_timing'].values())
    detailed=run/'phy/camera_to_dsi_display_pr.timing'
    if detailed.exists():
        txt=detailed.read_text()
        hdmi=txt.split('Path Group     :     HDMI_PIXEL_CLK -> HDMI_PIXEL_CLK',1)[1].split('Max Paths',1)[0]
        setup=re.search(r'Max\s*: SWNS\s+([-0-9.]+)ns, STNS\s+([-0-9.]+)ns',hdmi)
        hold=re.search(r'Min\s*: HWNS\s+([-0-9.]+)ns, HTNS\s+([-0-9.]+)ns',hdmi)
        summary['hdmi_domain_timing']={k:float(v) for k,v in zip(['SWNS','STNS','HWNS','HTNS'],[*setup.groups(),*hold.groups()])}
        summary['negative_paths']=[dict(slack_ns=float(m[0]),begin=m[1],end=m[2]) for m in
            re.findall(r'Slack\s*:\s*(-[0-9.]+)ns\s*\nBegin Point\s*:\s*([^\n]+)\nEnd Point\s*:\s*([^\n]+)',txt)]
    if job['status']!='running':
        for stage,suffix in [('syn','_gate.area'),('phy','_phy.area'),('phy','_phy.ts'),('phy','_pr.timing')]:
            path=run/stage/f'camera_to_dsi_display{suffix}'
            if path.exists():shutil.copy2(path,OUT/path.name)
        bit=run/'phy/camera_to_dsi_display.bit'
        if bit.exists():summary['bitstream']=dict(path=str(bit),bytes=bit.stat().st_size,sha256=hashlib.sha256(bit.read_bytes()).hexdigest())
    (OUT/'completion.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
