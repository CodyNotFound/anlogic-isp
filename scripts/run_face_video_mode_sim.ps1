param([string]$ModelSimBin='[LOCAL_PATH]',
 [string]$Python='[LOCAL_PATH]',
 [switch]$PoseUpdate,[string]$Variant='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($Variant -and $Variant -notmatch '^[A-Za-z0-9_]+$'){throw 'Invalid variant'}
$suffix=if($Variant){"_$Variant"}else{''}
$work=Join-Path $root "sim/face_lbp/work_video$suffix"
if(-not(Test-Path $work)){& (Join-Path $ModelSimBin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
Push-Location $root
try {
 & $Python scripts/face_video_mode_fixture.py
 if($LASTEXITCODE){throw 'Native photo fixture failed'}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work rtl/analytics/face_lbp/face_lbp_core.v rtl/analytics/face_lbp/face_candidate_select.v rtl/analytics/face_lbp/face_detector_snapshot.v rtl/analytics/face_lbp/face_pose_snapshot.v rtl/analytics/face_lbp/face_video_position.v rtl/analytics/face_lbp/face_position_overlay.v sim/face_lbp/tb_face_video_mode.sv sim/face_lbp/tb_face_position_overlay.sv sim/face_lbp/tb_face_video_timeout.sv sim/face_lbp/tb_face_video_result_ttl.sv
 if($LASTEXITCODE){throw 'Face video compile failed'}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work sim/face_lbp/tb_face_temporal.sv
 if($LASTEXITCODE){throw 'Face temporal compile failed'}
 foreach($test in @('tb_face_position_overlay','tb_face_video_timeout','tb_face_video_result_ttl','tb_face_temporal','tb_face_video_mode')){
  $reportDir=if($PoseUpdate){if($Variant){"reports/face_pose/$Variant/video"}else{'reports/face_pose/video'}}else{'reports/face_lbp'}
  $outDir=Join-Path $root $reportDir
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $log=Join-Path $outDir "$test.log"
  $extra=if($PoseUpdate -and $test -eq 'tb_face_video_mode'){@('-gCASE_START=3','-gCASE_END=4',"-gOUTPUT_DIR=$reportDir")}else{@()}
  & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work $test @extra -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $log
  $result=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -or $result -notmatch "PASS $test" -or $result -match 'FAIL|\*\* (Error|Fatal)'){throw "$test failed"}
 }
}finally{Pop-Location}
