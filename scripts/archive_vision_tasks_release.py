"""Archive a fully verified bit and evidence. Never programs hardware."""
from pathlib import Path
import argparse,hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[1]


def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--name',required=True);p.add_argument('--variant',default='r9');p.add_argument('--candidate-note',default='');args=p.parse_args()
    if not all(c.isalnum() or c=='_' for c in args.name):raise ValueError('Invalid archive name')
    out=ROOT/'reports/vision_tasks';summary=json.loads((out/'completion.json').read_text())
    if summary['build_run']!=args.run or summary.get('build_job',{}).get('status')!='passed' or not summary.get('routed_timing_passed'):
        raise ValueError('Build/timing not passed; no release archive')
    if not summary.get('native_task_suite_passed') or not summary.get('unit_functional_passed'):raise ValueError('Functional tests not passed')
    if summary.get('CDC_first_stage_D_pins_verified')!=4:raise ValueError('CDC constraint coverage not verified')
    dest=ROOT/'releases'/args.name
    if dest.exists():raise ValueError('Preserve existing release; use a fresh archive name')
    run=ROOT/'td_project'/args.run
    paths=[]
    for line in (run/'source_sha256.txt').read_text().splitlines():
        sha,rel=line.split('  ',1);src=ROOT/rel
        if hashlib.sha256(src.read_bytes()).hexdigest()!=sha.lower():raise ValueError(f'Stale source: {rel}')
        paths.append((src,dest/'source'/rel))
    extras=['td_project/camera_to_dsi_display.al','td_project/build_colorshading.ps1','scripts/run_td_verified.ps1',
        'scripts/run_vision_tasks_sim.ps1','scripts/vision_tasks_reference.py','scripts/vision_tasks_report.py',
        'scripts/archive_vision_tasks_release.py','scripts/run_td_constraint_revision.py','doc/vision_task_modes.md']
    extras += [str(f.relative_to(ROOT)) for f in (ROOT/'sim/vision_tasks').glob('*.sv')]
    if summary.get('rotation_tracking'):
        extras += ['scripts/vision_rotation_reference.py','scripts/vision_rotation_report.py','doc/vision_tracking_rotation.md']
        extras += ['scripts/run_face_pipeline_sim.ps1','scripts/run_frame_preamble_sim.ps1','scripts/run_osd_checks.ps1','scripts/on_td_complete.ps1',
            'sim/osd_font_rom.hex','sim/logo_idx.hex','sim/logo_pal.hex','sim/osd_rom_sim_models.v','sim/osd_rom_real_models.v',
            'sim/tb_ref_osd_mixer.v','sim/tb_mode_ctrl_ref_modes.v','sim/tb_pixel_algorithm_ref_modes.v','sim/face_lbp/tb_face_pipeline.sv',
            'sim/tb_isp_frame_preamble.v','sim/tb_video_in_frame_preamble.v']
        extras += [str(f.relative_to(ROOT)) for f in (ROOT/'sim/vision_tasks/rotation').glob('*') if f.is_file()]
        extras += [f'sim/face_lbp/data/{name}.jpg' for name in ['figurine','lena','fruits']]
        extras += [str(f.relative_to(ROOT)) for f in (ROOT/'user_source/hdl_source').glob('*.mif')]
    for rel in extras:paths.append((ROOT/rel,dest/'source'/rel))
    for sub in ['syn','phy']:
        for suffix in ['*.area','*.ts','*.timing','*.log','*.bit']:
            for src in (run/sub).glob(suffix):paths.append((src,dest/'build'/sub/src.name))
    paths.append((run/'source_sha256.txt',dest/'source_sha256.txt'))
    if (run/'checkpoint_provenance.json').exists():paths.append((run/'checkpoint_provenance.json',dest/'checkpoint_provenance.json'))
    selected=[out/'reference.json',out/'completion.json',out/f'functional_source_sha256_{args.variant}.json']
    if summary.get('rotation_tracking'):
        selected += [out/f'{name}.png' for name in ['tracker_hud_rtl','region_hud_rtl','full_osd_rtl','full_region_osd_rtl']]
        for pattern in ['*.json','*.csv','rtl*comparison.png','*_r2.log','build_r1_console.log','face_pipeline_r2_console.log']:
            selected += list((out/'rotation').glob(pattern))
        selected += list(out.glob('*_rot_r1.log'))+list(out.glob('*_rot_r2.log'))
    else:
        selected+=list(out.glob('*.png'))+list(out.glob('*_rtl.csv'))+list(out.glob(f'*_{args.variant}.log'))
    selected+=[out/f'face_pipeline_{args.variant}_console.log',
        (out/'rotation/report_final_console.log' if summary.get('rotation_tracking') else out/'report_final_console.log')]
    build_variant=args.run.rsplit('_',1)[-1]
    if not summary.get('rotation_tracking'):selected.append(out/f'build_{build_variant}_console.log')
    for src in selected:
        if summary.get('rotation_tracking') and src.name=='functional.json':continue
        if src.exists():paths.append((src,dest/'evidence'/src.name))
    for name in ['query_gate_o.log','query_place_o.log','verified_stage_safe_exception.timing','verify_stage_safe.log']:
        if summary.get('rotation_tracking'):continue
        src=out/'constraint_probe'/name
        if src.exists():paths.append((src,dest/'evidence/constraint_check'/name))
    origin=summary.get('constraint_revision_provenance',{}).get('base_run')
    if origin:
        src=ROOT/'td_project'/origin/'syn/synthesis.log'
        if src.exists():paths.append((src,dest/'origin_synthesis'/f'{origin}.log'))
    for src,dst in paths:dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
    (dest/'release.json').write_text(json.dumps(dict(run=args.run,source_files=summary['build_source_files_checked'],
        additional_MIF_assets=summary.get('additional_MIF_assets_checked',0),archive_bitstream_path='build/phy/camera_to_dsi_display.bit',
        modes=(dict(TRAK=12,REGN=14) if summary.get('rotation_tracking') else dict(TRAK=12,CLHE=13,REGN=14)),timing_passed=True,board_tested=False,candidate_only=bool(args.candidate_note),
        known_issue=args.candidate_note,
        bitstream=summary['bitstream'],area=summary['phy_area'],timing=summary['routed_timing'],
        dependency_note='Source snapshot restores into this repository with its generated vendor IP and the recorded TD installation; not a standalone SDK.'),indent=2))
    hashes={str(f.relative_to(dest)):hashlib.sha256(f.read_bytes()).hexdigest() for f in dest.rglob('*') if f.is_file()}
    (dest/'archive_sha256.json').write_text(json.dumps(hashes,indent=2));print('ARCHIVED',dest)


if __name__=='__main__':main()
