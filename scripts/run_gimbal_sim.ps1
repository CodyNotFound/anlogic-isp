param([string[]]$Tests=@('servo_gimbal','servo_production','gimbal_panel','gimbal_osd'),[string]$Variant='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$out=Join-Path $root 'reports/gimbal'
if($Variant){if($Variant -notmatch '^[A-Za-z0-9_]+$'){throw 'Invalid variant'};$out=Join-Path $out $Variant}
$work=Join-Path $out 'sim_work'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location $root
try {
 if(-not(Test-Path $work)){& (Join-Path $bin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 $sources=@('rtl/control/servo_gimbal_ctrl.v','rtl/control/gimbal_button_router.v','rtl/control/gimbal_panel.v',
 'rtl/control/switch_ctrl.v','rtl/analytics/vision_tasks/vision_bcd.v','rtl/overlay/gimbal_osd.v',
 'sim/tb_servo_gimbal.v','sim/tb_gimbal_panel.sv','sim/tb_gimbal_osd.sv')
 & (Join-Path $bin 'vlog.exe') -sv -work $work @sources
 if($LASTEXITCODE){throw 'gimbal compile failed'}
 foreach($test in $Tests){
  $log=Join-Path $out "tb_$test.log"
  & (Join-Path $bin 'vsim.exe') -c -lib $work "tb_$test" -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $result=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -ne 0 -or $result -notmatch "PASS tb_$test" -or $result -match '\*\* (Error|Fatal)'){throw "Failed $test"}
 }
}finally{Pop-Location}
