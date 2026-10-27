param([string]$Variant='r9',[switch]$SkipPrepare,[switch]$SkipIntegration,
[string[]]$Tests=@('helpers','sampler','tracker','region','region_overflow','clahe','task_suite','demo_cdc','legacy_fixes','hud','gaussian','task_osd'))
$ErrorActionPreference='Stop'
if($Variant -notmatch '^[A-Za-z0-9_]+$'){throw 'Invalid variant'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$python='[LOCAL_PATH]'
$bin='[LOCAL_PATH]'
$work=Join-Path $root "sim/vision_tasks/work_$Variant"
$out=Join-Path $root 'reports/vision_tasks'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location $root
try{
 if(-not $SkipPrepare){& $python scripts/vision_tasks_reference.py;if($LASTEXITCODE){throw 'Fixture preparation failed'}}
 if(-not(Test-Path -LiteralPath $work)){& (Join-Path $bin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 $sources=@(Get-ChildItem rtl/analytics/vision_tasks -Filter '*.v' | ForEach-Object {$_.FullName})
 $sources+=Join-Path $root 'rtl/control/vision_demo_cdc.v'
 $sources+=Join-Path $root 'rtl/isp/pixel_algorithm.v'
 $sources+=Join-Path $root 'rtl/isp/pixel_cartoon.v'
 $sources+=@('rtl/app/vision_pipeline.v','rtl/control/mode_ctrl.v','rtl/control/switch_ctrl.v',
   'rtl/isp/auto_exposure.v','rtl/isp/auto_white_balance.v','rtl/isp/histogram_equalizer.v','rtl/overlay/adaptive_brightness.v',
   'user_source/hdl_source/hdmi_mixer.v')
 $sources+=Get-ChildItem rtl/analytics/face_lbp -Filter '*.v' | ForEach-Object {$_.FullName}
 $sources+=Get-ChildItem sim/vision_tasks -Filter '*.sv' | ForEach-Object {$_.FullName}

 $sources+=@('rtl/control/servo_gimbal_ctrl.v','rtl/control/gimbal_button_router.v','rtl/control/gimbal_panel.v','rtl/overlay/gimbal_osd.v')
 & (Join-Path $bin 'vlog.exe') -sv "+incdir+$root/rtl/app" -work $work @sources
 if($LASTEXITCODE){throw 'Task RTL compile failed'}
 $jobs=@()
 foreach($test in $Tests){
  $top=if($test -eq 'region_overflow'){'tb_vision_region'}elseif($test -eq 'scale_negative'){'tb_vision_scale'}else{"tb_vision_$test"}
  $log=Join-Path $out "${test}_${Variant}.log"
  $args=@('-c','-lib',$work,$top,'-l',$log)
  if($test -eq 'region_overflow'){$args+=@('-gCAPACITY=32','-gCASE_FILE=sim/vision_tasks/region_overflow_cases.txt','-gCSV_FILE=reports/vision_tasks/region_overflow_rtl.csv')}
  if($test -eq 'scale_negative'){$args+=@('-gCASE_FILE=sim/vision_tasks/scale_v40/negative_cases.txt','-gCSV_FILE=reports/vision_tasks/scale_v40/negative_rtl.csv','-gEXPECTED_FRAMES=4')}
  $args+=@('-do','"onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0"')
  $proc=Start-Process -FilePath (Join-Path $bin 'vsim.exe') -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $out "${test}_${Variant}_console.log") -RedirectStandardError (Join-Path $out "${test}_${Variant}_stderr.log")
  $jobs+=@{name=$test;top=$top;proc=$proc;log=$log}
 }
 $failed=@()
 foreach($job in $jobs){
  $job.proc.WaitForExit();$content=[IO.File]::ReadAllText($job.log)
  if($job.proc.ExitCode -ne 0 -or $content -notmatch "PASS $($job.top)" -or $content -match 'FAIL|\*\* (Error|Fatal)'){$failed+=$job.name;Write-Output "FAIL $($job.name)"}
  else{Write-Output "PASS $($job.name)"}
 }
 if($failed.Count){throw "Task tests failed: $($failed -join ', ')"}
 if(-not $SkipIntegration){
  & scripts/run_face_pipeline_sim.ps1 -Variant "v34_tasks_$Variant" *> (Join-Path $out "face_pipeline_${Variant}_console.log")
  if(-not $?){throw 'Existing face/passthrough integration failed'}
  & scripts/run_frame_preamble_sim.ps1 *> (Join-Path $out "isp_cdc_regression_${Variant}.log")
  if(-not $?){throw 'ISP preamble regression failed'}
  & scripts/run_osd_checks.ps1 *> (Join-Path $out "legacy_osd_${Variant}.log")
  if(-not $?){throw 'Existing OSD/button/pixel regression failed'}
 }
}finally{Pop-Location}
