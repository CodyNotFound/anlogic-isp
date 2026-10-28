param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$out=Join-Path $root 'reports/tracking'
$work=Join-Path $out 'work'
New-Item -ItemType Directory -Force $out | Out-Null
if(!(Test-Path $work)){& "$bin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
$files=@(Get-ChildItem (Join-Path $root 'rtl/analytics/vision_tasks'),(Join-Path $root 'rtl/analytics/face_cnn') -Filter '*.v' | ForEach-Object {$_.FullName})
$files+=@('sim/tb_motion_v62.sv','sim/vision_tasks/tb_vision_region_identity.sv','sim/vision_tasks/tb_reacquire_production_v65.sv')
Push-Location $root
try {
 & "$bin/vlog.exe" -sv -work $work @files *> (Join-Path $out 'compile.log')
 if($LASTEXITCODE){throw 'Tracking compile failed'}
 foreach($top in @('tb_motion_v62','tb_vision_region_identity','tb_reacquire_production_v65')){
  $log=Join-Path $out "$top.log"
  & "$bin/vsim.exe" -c -lib $work $top -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $text=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -or $text -notmatch "PASS $top" -or $text -match '\*\* (Error|Fatal)'){throw "Failed $top"}
 }
}finally{Pop-Location}
