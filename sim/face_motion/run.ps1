param([string]$ModelSimBin='[LOCAL_PATH]',[string]$PhotoFixtures='', [string]$PhotoPython='python')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $root 'build/experiments/face_fast_regression'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$work=Join-Path $out 'work'
if(!(Test-Path -LiteralPath $work)){& "$ModelSimBin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
if($PhotoFixtures){
 & $PhotoPython (Join-Path $PSScriptRoot 'make_photo_vectors.py') --fixtures $PhotoFixtures --out (Join-Path $out 'photos')
 if($LASTEXITCODE){throw 'Photo vector generation failed'}
}
& "$ModelSimBin/vlog.exe" -sv -work $work (Join-Path $root 'rtl/analytics/face_cnn/face_patch_motion.v') (Join-Path $PSScriptRoot 'tb_face_patch_motion.sv') (Join-Path $root 'rtl/analytics/face_cnn/face_motion_fusion.v') (Join-Path $PSScriptRoot 'tb_face_motion_fusion.sv') (Join-Path $PSScriptRoot 'tb_face_motion_photos.sv') *> (Join-Path $out 'compile.log')
if($LASTEXITCODE){throw 'RTL compile failed'}
$tops=@('tb_face_patch_motion','tb_face_motion_fusion');if($PhotoFixtures){$tops+='tb_face_motion_photos'}
foreach($top in $tops){
 $logPath=Join-Path $out ($top+'.log')
 $extra=@();if($top -eq 'tb_face_motion_photos'){$extra=@("+DATA_DIR="+((Join-Path $out 'photos').Replace('\','/')))}
 & "$ModelSimBin/vsim.exe" -c -lib $work $top @extra -l $logPath -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $rc=$LASTEXITCODE;$log=[IO.File]::ReadAllText($logPath)
 if($rc -or $log -notmatch ("PASS "+$top) -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "Face motion regression failed: $top"}
}
