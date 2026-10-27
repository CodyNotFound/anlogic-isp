$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$out=Join-Path $root 'reports/gimbal/v38_final'
$work=Join-Path $out 'speed_work'
Push-Location $root
try {
 if(-not(Test-Path $work)){& (Join-Path $bin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 & (Join-Path $bin 'vlog.exe') -sv -work $work rtl/control/servo_gimbal_ctrl.v reports/gimbal/v38_final/servo_v37_baseline.v sim/tb_gimbal_speed.sv
 if($LASTEXITCODE){throw 'Speed benchmark compile failed'}
 $log=Join-Path $out 'tb_gimbal_speed.log'
 & (Join-Path $bin 'vsim.exe') -c -lib $work tb_gimbal_speed -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $result=[IO.File]::ReadAllText($log)
 if($LASTEXITCODE -or $result -notmatch 'PASS tb_gimbal_speed' -or $result -match '\*\* (Error|Fatal)'){throw 'Speed benchmark failed'}
 $latencyWork=Join-Path $out 'latency_work'
 if(-not(Test-Path $latencyWork)){& (Join-Path $bin 'vlib.exe') $latencyWork;if($LASTEXITCODE){throw 'Latency vlib failed'}}
 & (Join-Path $bin 'vlog.exe') -sv -work $latencyWork rtl/analytics/vision_tasks/vision_sad_tracker.v rtl/analytics/vision_tasks/vision_color_region.v rtl/analytics/vision_tasks/vision_unsigned_divider.v sim/tb_gimbal_analysis_latency.sv
 if($LASTEXITCODE){throw 'Latency compile failed'}
 $latencyLog=Join-Path $out 'tb_gimbal_analysis_latency.log'
 & (Join-Path $bin 'vsim.exe') -c -lib $latencyWork tb_gimbal_analysis_latency -l $latencyLog -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $result=[IO.File]::ReadAllText($latencyLog)
 if($LASTEXITCODE -or $result -notmatch 'PASS tb_gimbal_analysis_latency' -or $result -match '\*\* (Error|Fatal)'){throw 'Analysis latency test failed'}
}finally{Pop-Location}
