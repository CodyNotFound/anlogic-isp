param([string]$ModelSimBin='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root 'build/experiments/face_fast_regression'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$work=Join-Path $out 'work'
if(!(Test-Path -LiteralPath $work)){& "$ModelSimBin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
& "$ModelSimBin/vlog.exe" -sv -work $work (Join-Path $root 'rtl/analytics/face_cnn/face_patch_motion.v') (Join-Path $PSScriptRoot 'tb_face_patch_motion.sv') (Join-Path $root 'rtl/analytics/face_cnn/face_motion_fusion.v') (Join-Path $PSScriptRoot 'tb_face_motion_fusion.sv') *> (Join-Path $out 'compile.log')
if($LASTEXITCODE){throw 'RTL compile failed'}
foreach($top in @('tb_face_patch_motion','tb_face_motion_fusion')){
 $logPath=Join-Path $out ($top+'.log')
 & "$ModelSimBin/vsim.exe" -c -lib $work $top -l $logPath -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $rc=$LASTEXITCODE;$log=[IO.File]::ReadAllText($logPath)
 if($rc -or $log -notmatch ("PASS "+$top) -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "Face motion regression failed: $top"}
}
