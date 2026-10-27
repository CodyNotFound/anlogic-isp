param([string]$ModelSimBin='[LOCAL_PATH]',[string]$Variant='',[ValidateSet('tb_face_pipeline','tb_gimbal_pipeline','tb_gimbal_target','tb_region_buttons','tb_cartoon_pipeline','tb_field_pipeline')][string]$Test='tb_face_pipeline')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($Variant -and $Variant -notmatch '^[A-Za-z0-9_]+$'){throw 'Invalid variant'}
$suffix=if($Variant){"_$Variant"}else{''}
$work=Join-Path $root "sim/face_lbp/work_pipeline$suffix"
if(-not(Test-Path $work)){& (Join-Path $ModelSimBin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
Push-Location $root
try {
 $sources=@('rtl/control/mode_ctrl.v','rtl/control/switch_ctrl.v','rtl/isp/auto_exposure.v','rtl/isp/auto_white_balance.v','rtl/isp/histogram_equalizer.v','rtl/isp/pixel_cartoon.v','rtl/isp/pixel_algorithm.v','rtl/overlay/adaptive_brightness.v','rtl/app/vision_pipeline.v','user_source/hdl_source/hdmi_mixer.v',
 'rtl/analytics/face_lbp/face_lbp_core.v','rtl/analytics/face_lbp/face_candidate_select.v','rtl/analytics/face_lbp/face_detector_snapshot.v','rtl/analytics/face_lbp/face_pose_snapshot.v','rtl/analytics/face_lbp/face_video_position.v','rtl/analytics/face_lbp/face_position_overlay.v','sim/face_lbp/tb_face_pipeline.sv','sim/cartoon/tb_cartoon_pipeline.sv')
 $sources += Get-ChildItem -LiteralPath (Join-Path $root 'rtl/analytics/vision_tasks') -Filter '*.v' | ForEach-Object {$_.FullName}
 $sources += Join-Path $root 'sim/cartoon/tb_field_pipeline.sv'

 $sources+=@('sim/tb_gimbal_pipeline.sv','sim/tb_gimbal_target.sv','sim/tb_region_buttons.sv')
 $sources+=@('rtl/control/servo_gimbal_ctrl.v','rtl/control/gimbal_button_router.v','rtl/control/gimbal_panel.v','rtl/overlay/gimbal_osd.v')
 & (Join-Path $ModelSimBin 'vlog.exe') -sv "+incdir+$root/rtl/app" -work $work @sources
 if($LASTEXITCODE){throw 'Application compile failed'}
 $outDir=if($Variant){Join-Path $root "reports/face_pose/$Variant"}else{Join-Path $root 'reports/face_lbp'}
 New-Item -ItemType Directory -Force -Path $outDir | Out-Null
 $log=Join-Path $outDir "$Test.log"
 & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work $Test -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $log
 $result=[IO.File]::ReadAllText($log)
 if($LASTEXITCODE -or $result -notmatch "PASS $Test" -or $result -match 'FAIL|\*\* (Error|Fatal)'){throw 'Application integration simulation failed'}
}finally{Pop-Location}
