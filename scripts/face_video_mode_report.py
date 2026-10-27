"""Validate face-mode simulation evidence and capture current integrated build status."""
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/face_lbp'
RUN='colorshading_runs_20261019_v32_face_mode_r3'


def area(path):
    s=path.read_text()
    return {key:int(re.search(r'(?m)^#'+pattern+r'\s+(\d+)',s)[1]) for key,pattern in
            [('slices',r'slice\*?'),('eram','eram'),('dsp','dsp')]}


def main():
    for test in ['tb_face_video_mode','tb_face_video_timeout','tb_face_position_overlay','tb_face_pipeline']:
        log=(OUT/f'{test}.log').read_text()
        if f'PASS {test}' not in log or re.search(r'FAIL|\*\* (Fatal|Error)',log):
            raise ValueError(f'Incomplete or failed simulation: {test}')
    mode_log=(OUT/'mode_regression_console.log').read_text()
    for test in ['tb_ref_osd_mixer','tb_pixel_algorithm_ref_modes','tb_mode_ctrl_ref_modes']:
        if f'PASS {test}' not in mode_log:raise ValueError(f'Missing regression: {test}')
    rows=list(csv.DictReader((OUT/'video_mode_rtl.csv').open()))
    if [r['name'] for r in rows]!=['photo_left','photo_right','fruits_negative','lena_video']:
        raise ValueError('Incomplete photo results')
    for row in rows:
        target=list(map(int,(ROOT/'sim/face_lbp'/f"{row['name']}.target").read_text().split()))
        if int(row['found'])!=target[0] or [int(row[k]) for k in ['x','y','size']]!=[v*8 for v in target[2:5]]:
            raise ValueError('Position mismatch')
        if int(row['samples'])!=14400:raise ValueError('Incomplete downsample raster')
    ppm=OUT/'lena_video_rtl.ppm'
    data=ppm.read_bytes()
    header=b'P6\n1280 720\n255\n'
    if not data.startswith(header) or len(data)!=len(header)+1280*720*3:
        raise ValueError('RTL overlay image is incomplete')
    with Image.open(ppm) as im:
        if im.size!=(1280,720):raise ValueError('Wrong image dimensions')
        im.save(OUT/'lena_video_rtl.png')
        preview=im.resize((960,540),Image.Resampling.LANCZOS)
        preview.save(OUT/'lena_video_rtl_preview.png')
    manifest={}
    for entry in (ROOT/'td_project'/RUN/'source_sha256.txt').read_text().splitlines():
        digest,path=entry.split('  ',1)
        actual=hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
        if digest.lower()!=actual:raise ValueError(f'Build input changed: {path}')
        manifest[path]=actual
    (OUT/'video_mode_sources.json').write_text(json.dumps(manifest,indent=2))
    job=json.loads((ROOT/'doc/compile/v32_face_mode_r3_job.json').read_text(encoding='utf-8-sig'))
    summary=dict(mode=11,label='FACE',inference='FPGA LBP frontal face position, no identity recognition',
        rtl_integrated_in_camera_project=True,simulated_photo_cases=rows,
        downsample_photo_values_checked=57600,rgb_average_probe_values_checked=14400,
        application_pixels_checked=1843200,overlay_pixels_checked=9216,
        full_application_test_uses_injected_result=True,
        photo_detection_test_uses_actual_cascade=True,
        busy_frame_rejection=True,malformed_frame_abort=True,stalled_camera_timeout_recovery=True,
        mode_exit_verified=True,baseline_modes_regression_passed=True,
        independent_accuracy_evaluation=False,board_tested=False,gimbal_control_implemented=False,
        build_run=RUN,build_job=job,source_files_checked=len(manifest),
        limitations=['Minimum face window corresponds to about 192 source pixels width.',
                     'Tilt, occlusion and small faces can be missed.',
                     'Simulation photos do not establish live camera recognition accuracy.'])
    run=ROOT/'td_project'/RUN
    gate=run/'syn/camera_to_dsi_display_gate.area'
    phy=run/'phy/camera_to_dsi_display_phy.area'
    if gate.exists():summary['integrated_gate_area']=area(gate)
    if phy.exists():summary['integrated_routed_area']=area(phy)
    timing=run/'phy/camera_to_dsi_display_phy.ts'
    if timing.exists():
        txt=timing.read_text()
        summary['routed_timing']={k:float(re.search(k+r':\s*([-0-9.]+)ns',txt)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
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
        for path in [run/'source_sha256.txt',gate,phy,timing,detailed,
                     ROOT/'doc/compile/v32_face_mode_r3_completion.json']:
            if path.exists():shutil.copy2(path,OUT/('video_mode_integrated_'+path.name))
    bit=run/'phy/camera_to_dsi_display.bit'
    if bit.exists():summary['bitstream']=dict(path=str(bit),bytes=bit.stat().st_size,sha256=hashlib.sha256(bit.read_bytes()).hexdigest())
    summary['ready_for_board_signoff']=job['status']=='passed' and summary.get('routed_timing_passed',False)
    (OUT/'video_mode_completion.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
