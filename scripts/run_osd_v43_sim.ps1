param([string]$Variant='r1')
$ErrorActionPreference='Stop'
if($Variant -notmatch '^[A-Za-z0-9_]+$'){throw 'Invalid variant'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$out=Join-Path $root 'reports/osd_v43'
$work=Join-Path $out "work_$Variant"
Push-Location $root
try{
 New-Item -ItemType Directory -Force -Path $out | Out-Null
 & '[LOCAL_PATH]' scripts/osd_v43_reference.py
 if($LASTEXITCODE){throw 'OSD reference preparation failed'}
 if(-not(Test-Path $work)){& (Join-Path $bin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 $sources=@('rtl/app/vision_pipeline.v','rtl/control/mode_ctrl.v','rtl/control/switch_ctrl.v',
 'rtl/control/servo_gimbal_ctrl.v','rtl/control/gimbal_button_router.v','rtl/control/gimbal_panel.v',
 'rtl/overlay/gimbal_osd.v','rtl/overlay/adaptive_brightness.v',
 'rtl/isp/auto_exposure.v','rtl/isp/auto_white_balance.v','rtl/isp/histogram_equalizer.v',
 'rtl/isp/pixel_algorithm.v','rtl/isp/pixel_cartoon.v','user_source/hdl_source/hdmi_mixer.v')
 $sources+=Get-ChildItem rtl/analytics/vision_tasks -Filter '*.v' | ForEach-Object {$_.FullName}
 $sources+=Get-ChildItem rtl/analytics/face_lbp -Filter '*.v' | ForEach-Object {$_.FullName}
 $sources+='sim/tb_osd_v43.sv'
 & (Join-Path $bin 'vlog.exe') -sv "+incdir+$root/rtl/app" -work $work @sources *> (Join-Path $out "compile_$Variant.log")
 if($LASTEXITCODE){throw "OSD compile failed: compile_$Variant.log"}
 $log=Join-Path $out "tb_osd_v43_$Variant.log"
 & (Join-Path $bin 'vsim.exe') -c -lib $work tb_osd_v43 -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $text=[IO.File]::ReadAllText($log)
 if($LASTEXITCODE -or $text -notmatch 'PASS tb_osd_v43' -or $text -match '\*\* (Error|Fatal)|\bFAIL\b'){throw 'Compact OSD regression failed'}
}finally{Pop-Location}
