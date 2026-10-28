param([string]$ModelSimBin='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root 'build/experiments/face_fast_regression'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$work=Join-Path $out 'work'
if(!(Test-Path -LiteralPath $work)){& "$ModelSimBin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
& "$ModelSimBin/vlog.exe" -sv -work $work (Join-Path $PSScriptRoot 'face_patch_motion.v') (Join-Path $PSScriptRoot 'tb_face_patch_motion.sv') *> (Join-Path $out 'compile.log')
if($LASTEXITCODE){throw 'RTL compile failed'}
& "$ModelSimBin/vsim.exe" -c -lib $work tb_face_patch_motion -l (Join-Path $out 'test.log') -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
$rc=$LASTEXITCODE
$log=[IO.File]::ReadAllText((Join-Path $out 'test.log'))
if($rc -or $log -notmatch 'PASS tb_face_patch_motion' -or $log -notmatch 'Errors: 0, Warnings: 0'){throw 'Face motion regression failed'}
