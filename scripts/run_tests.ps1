param(
 [ValidateSet('tone','osd','network','controls','tracking','isp','ddr')][string[]]$Tests=@('tone','osd','network','controls','tracking','isp','ddr'),
 [string]$PythonExe="$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
function Simulate([string]$name,[string]$top,[string[]]$files,[string[]]$includes=@(),[string]$cwd=$root){
 $out=Join-Path $root "reports/${name}_v74"
 $work=Join-Path $out 'work'
 New-Item -ItemType Directory -Force $out | Out-Null
 if(!(Test-Path $work)){& "$bin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
 & "$bin/vlog.exe" -sv @includes -work $work @files *> (Join-Path $out 'compile.log')
 if($LASTEXITCODE){throw "$name compile failed"}
 Push-Location $cwd
 try{& "$bin/vsim.exe" -c -lib $work $top -l (Join-Path $out 'test.log') -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'}finally{Pop-Location}
 $log=[IO.File]::ReadAllText((Join-Path $out 'test.log'))
 if($LASTEXITCODE -or $log -notmatch "PASS $top" -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "$name verification failed"}
}
Push-Location $root
try{
 if($Tests -contains 'tone'){
  Simulate -name 'tone' -top 'tb_tone_exact_v73' -files @('rtl/isp/color_tone4.v','sim/reference/color_tone4_ref.v','sim/tb_tone_exact_v73.sv') -includes @('+incdir+rtl/isp')
 }
 if($Tests -contains 'osd'){
  New-Item -ItemType Directory -Force reports/osd_v73 | Out-Null
  Simulate -name 'osd' -top 'tb_osd_v73' -files @('rtl/hardware/hdl_source/hdmi_mixer.v','sim/osd_rom_full_models.v','sim/tb_osd_v73.sv') -cwd (Join-Path $root 'sim')
  & $PythonExe scripts/check_osd.py
  if($LASTEXITCODE){throw 'OSD reference comparison failed'}
 }
 if($Tests -contains 'network'){
  Simulate -name 'cnn' -top 'tb_yunet_network_v73' -files @('rtl/analytics/face_cnn/yunet_dot4.v','rtl/analytics/face_cnn/yunet_network.v','sim/face_cnn/tb_yunet_network_v73.sv') -includes @('+incdir+rtl/analytics/face_cnn')
 }
 if($Tests -contains 'controls'){& ./scripts/run_controls_tests.ps1}
 if($Tests -contains 'tracking'){& ./scripts/run_tracking_tests.ps1}
 if($Tests -contains 'isp'){& ./scripts/run_isp_tests.ps1}
 if($Tests -contains 'ddr'){& ./scripts/run_ddr_tests.ps1}
}finally{Pop-Location}
