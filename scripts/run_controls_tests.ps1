param([string]$Test='all')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$out=Join-Path $root 'reports/hmi_v72'
$work=Join-Path $out 'regression_work'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location $root
try {
 if(-not(Test-Path $work)){& "$bin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
 $sources=Get-ChildItem (Join-Path $root 'rtl') -Recurse -Filter '*.v' | Where-Object {$_.FullName -notmatch '[\\/]rtl[\\/](hardware|vendor)[\\/]'} | ForEach-Object {$_.FullName}
 & "$bin/vlog.exe" -sv "+incdir+$root/rtl/app" -work $work @sources 'rtl/hardware/hdl_source/hdmi_mixer.v' 'sim/osd_rom_sim_models.v' 'sim/tb_hmi_v72.sv' 'sim/tb_hmi_pipeline_v72.sv' 'sim/tb_latency_v72.sv'
 if($LASTEXITCODE){throw 'compile failed'}
 $tests=if($Test -eq 'all'){@('tb_hmi_v72','tb_latency_v72','tb_hmi_pipeline_v72')}else{@($Test)}
 Push-Location $root
 try {foreach($name in $tests){
  if($name -notin @('tb_hmi_v72','tb_latency_v72','tb_hmi_pipeline_v72')){throw 'Invalid test'}
  $log=Join-Path $out "$name.log"
  & "$bin/vsim.exe" -c -lib $work $name -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $s=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -or $s -notmatch "PASS $name" -or $s -match '\*\* (Error|Fatal|Warning)' -or $s -notmatch 'Errors: 0, Warnings: 0'){throw "Failed $name"}
 }}finally{Pop-Location}
}finally{Pop-Location}
