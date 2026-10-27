param(
 [string]$ModelSimBin='[LOCAL_PATH]',
 [string]$Python='[LOCAL_PATH]',
 [switch]$SkipPrepare
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path $root 'sim/face_lbp/work'
Push-Location $root
try {
 if(-not $SkipPrepare){
  & $Python scripts/face_lbp_prepare.py
  if($LASTEXITCODE -ne 0){throw 'Fixture/model generation failed'}
 }
 if(-not (Test-Path $work)){
  & (Join-Path $ModelSimBin 'vlib.exe') $work
  if($LASTEXITCODE -ne 0){throw 'vlib failed'}
 }
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work rtl/analytics/face_lbp/face_lbp_core.v rtl/analytics/face_lbp/face_candidate_select.v rtl/analytics/face_lbp/face_detector_snapshot.v sim/face_lbp/tb_face_lbp.sv sim/face_lbp/tb_face_lbp_protocol.sv
 if($LASTEXITCODE -ne 0){throw 'vlog failed'}
 $log=Join-Path $root 'reports/face_lbp/modelsim.log'
 & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work tb_face_lbp -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $log
 $result=[IO.File]::ReadAllText($log)
 if($LASTEXITCODE -ne 0 -or $result -notmatch 'PASS ALL' -or $result -match 'FAIL|\*\* Error|\*\* Fatal'){
  throw 'Face LBP RTL simulation failed; inspect reports/face_lbp/modelsim.log'
 }
 $protocolLog=Join-Path $root 'reports/face_lbp/protocol.log'
 & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work tb_face_lbp_protocol -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $protocolLog
 $protocol=[IO.File]::ReadAllText($protocolLog)
 if($LASTEXITCODE -ne 0 -or $protocol -notmatch 'PASS protocol' -or $protocol -match 'FAIL|\*\* Error|\*\* Fatal'){throw 'Protocol simulation failed'}
 & $Python scripts/face_lbp_report.py
 if($LASTEXITCODE -ne 0){throw 'RTL evidence/report validation failed'}
} finally {Pop-Location}
