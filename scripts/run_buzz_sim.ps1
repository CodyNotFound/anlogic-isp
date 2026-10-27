param([string]$ModelSimBin='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=Join-Path $root 'reports/gimbal/buzz_sim'
$work=Join-Path $out 'work'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location $root
try {
 if(-not(Test-Path -LiteralPath $work)) {
  & (Join-Path $ModelSimBin 'vlib.exe') $work
  if($LASTEXITCODE){throw 'vlib failed'}
 }
 & (Join-Path $ModelSimBin 'vlog.exe') -work $work rtl/control/buzz_ctrl.v sim/tb_buzz_ctrl.v
 if($LASTEXITCODE){throw 'vlog failed'}
 foreach($test in @('tb_buzz_ctrl','tb_buzz_production')) {
  $log=Join-Path $out "$test.log"
  & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work $test -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $log
  $result=[IO.File]::ReadAllText($log)
  $marker=if($test -eq 'tb_buzz_ctrl'){'TB_BUZZ_PASS'}else{'TB_BUZZ_PRODUCTION_PASS'}
  if($LASTEXITCODE -ne 0 -or $result -notmatch $marker -or $result -match '\*\* (Error|Fatal)') {
   throw "Simulation failed: $test"
  }
 }
} finally { Pop-Location }
