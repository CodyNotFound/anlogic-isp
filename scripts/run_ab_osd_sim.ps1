$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$work=Join-Path $root 'reports/gimbal/ab_work'
Push-Location $root
try {
 if(-not(Test-Path $work)){& (Join-Path $bin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 $sources=@('rtl/app/vision_pipeline.v','rtl/control/mode_ctrl.v','rtl/control/switch_ctrl.v',
 'rtl/control/servo_gimbal_ctrl.v','rtl/control/gimbal_button_router.v','rtl/control/gimbal_panel.v','rtl/overlay/gimbal_osd.v',
 'rtl/isp/auto_exposure.v','rtl/isp/auto_white_balance.v','rtl/isp/histogram_equalizer.v','rtl/isp/pixel_cartoon.v','rtl/isp/pixel_algorithm.v',
 'rtl/overlay/adaptive_brightness.v','user_source/hdl_source/hdmi_mixer.v','sim/osd_rom_real_models.v','sim/tb_ab_before_osd.v')
 $sources+=Get-ChildItem rtl/analytics/vision_tasks,rtl/analytics/face_lbp -Filter '*.v' | ForEach-Object {$_.FullName}
 & (Join-Path $bin 'vlog.exe') -sv "+incdir+$root/rtl/app" -work $work @sources
 if($LASTEXITCODE){throw 'AB compile failed'}
 Push-Location sim
 try {
  $log=Join-Path $root 'reports/gimbal/ab_osd.log'
  & (Join-Path $bin 'vsim.exe') -c -lib $work tb_ab_before_osd -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $text=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -or $text -notmatch 'PASS tb_ab_before_osd' -or $text -match '\*\* (Error|Fatal)'){throw 'AB composition regression failed'}
 }finally{Pop-Location}
}finally{Pop-Location}
