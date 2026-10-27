param([string]$ModelSimBin='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path $root 'sim/face_pose/work_legacy_r3'
if(-not(Test-Path $work)){& (Join-Path $ModelSimBin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
Push-Location $root
try {
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work rtl/analytics/face_lbp/face_lbp_core.v rtl/analytics/face_lbp/face_candidate_select.v sim/face_lbp/tb_face_lbp.sv
 if($LASTEXITCODE){throw 'Legacy compile failed'}
 $log=Join-Path $root 'reports/face_pose/r3/legacy_anime_modelsim.log'
 & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work tb_face_lbp '-gCASES_FILE=sim/face_pose/legacy_anime_cases.txt' '-gOUTPUT_FILE=reports/face_pose/r3/legacy_anime_rtl.csv' -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $log
 $result=[IO.File]::ReadAllText($log)
 if($LASTEXITCODE -or $result -notmatch 'PASS ALL LBP RTL fixtures' -or $result -match 'FAIL|\*\* (Error|Fatal)'){throw 'Legacy dual-model compatibility test failed'}
}finally{Pop-Location}
