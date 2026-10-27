param([string]$ModelSimBin='[LOCAL_PATH]',
 [string]$Python='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path $root 'sim/face_lbp/work_selector_v40'
Push-Location $root
try {
 & $Python scripts/face_selector_vectors.py
 if($LASTEXITCODE){throw 'Selector vectors failed'}
 if(-not(Test-Path $work)){& (Join-Path $ModelSimBin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work rtl/analytics/face_lbp/face_lbp_core.v rtl/analytics/face_lbp/face_candidate_select.v rtl/analytics/face_lbp/face_detector_snapshot.v sim/face_lbp/tb_face_lbp_protocol.sv sim/face_lbp/tb_face_selector.sv
 if($LASTEXITCODE){throw 'Selector compile failed'}
 foreach($top in @('tb_face_lbp_protocol','tb_face_selector')){
  $name=if($top -eq 'tb_face_selector'){'selector'}else{'protocol'}
  $log=Join-Path $root "reports/tracking_v40/${name}_r4.log"
  & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work $top -l $log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $s=Get-Content -LiteralPath $log -Raw
  if($LASTEXITCODE -or $s -notmatch 'PASS' -or $s -match '\*\* (Error|Fatal)|\bFAIL\b'){throw "$top failed"}
 }
}finally{Pop-Location}
