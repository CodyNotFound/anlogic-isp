"""Retain a completed, timing-correct face-mode bit and its evidence, without programming hardware."""
from pathlib import Path
import hashlib
import json
import shutil
from face_video_mode_report import ROOT, OUT, RUN, main as report


def main():
    report()
    summary=json.loads((OUT/'video_mode_completion.json').read_text())
    job=summary['build_job']
    if job['status']!='passed' or not summary.get('routed_timing_passed'):
        raise ValueError('No release: integrated build or final setup/hold check has not passed')
    dest=ROOT/'releases/face_mode_v32_r3'
    if dest.exists():raise ValueError('Preserve existing archive; do not overwrite it')
    dest.mkdir(parents=True)
    build=ROOT/'td_project'/RUN
    files=[build/'phy'/f'camera_to_dsi_display{suffix}' for suffix in ['.bit','_phy.area','_phy.ts','_pr.timing','_exception.timing']]
    files += [build/'source_sha256.txt',OUT/'video_mode_completion.json',OUT/'video_mode_sources.json',
              ROOT/'doc/compile/v32_face_mode_r3_completion.json',ROOT/'doc/compile/v32_face_mode_r3_job.json',
              OUT/'lena_video_rtl.png',OUT/'video_mode_rtl.csv']
    for path in files:
        if path.exists():shutil.copy2(path,dest/path.name)
    # Retain the exact selected RTL/ROM inputs, plus project/constraints/scripts,
    # so useful bitstreams remain associated with their source state.
    sources=json.loads((OUT/'video_mode_sources.json').read_text())
    for rel in list(sources)+['td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display.sdc',
                              'rtl/config/vision_config.vh','td_project/build_colorshading.ps1',
                              'scripts/run_td_verified.ps1','doc/face_mode.md']:
        path=ROOT/rel
        target=dest/'source'/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(path,target)
    records={str(p.relative_to(dest)):hashlib.sha256(p.read_bytes()).hexdigest() for p in dest.rglob('*') if p.is_file()}
    (dest/'archive_sha256.json').write_text(json.dumps(records,indent=2))
    (dest/'release.json').write_text(json.dumps(dict(mode=11,label='FACE',run=RUN,
        timing_passed=True,board_tested=False,gimbal_control_implemented=False,
        routed_area=summary['integrated_routed_area'],routed_timing=summary['routed_timing'],
        bitstream=summary['bitstream'],usage='From mode 00 press K2 once to enter 11 FACE. Green box / red center.',
        limitation='Close frontal faces; minimum window about 192 source pixels wide.'),indent=2))
    print('ARCHIVED',dest)


if __name__=='__main__':main()
