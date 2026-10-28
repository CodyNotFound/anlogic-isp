param([string]$PythonExe="$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));Push-Location $root
try{
 & $PythonExe sim/face_cnn/check_head_offsets.py
 if($LASTEXITCODE){throw 'fixture failed'}
 $bin='[LOCAL_PATH]';$work=Join-Path $root 'build/head_offsets/work'
 if(!(Test-Path $work)){& "$bin/vlib.exe" $work}
 & "$bin/vlog.exe" -sv +incdir+rtl/analytics/face_cnn -work $work rtl/analytics/face_cnn/yunet_dot4.v rtl/analytics/face_cnn/yunet_network.v rtl/analytics/face_cnn/yunet_decode.v rtl/analytics/face_cnn/yunet_position_snapshot.v sim/face_cnn/tb_yunet_head_offsets.sv *> build/head_offsets/compile.log
 if($LASTEXITCODE){throw 'scanner compile failed'}
 & "$bin/vsim.exe" -c -lib $work tb_yunet_head_offsets -l build/head_offsets/test.log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $log=[IO.File]::ReadAllText((Join-Path $root 'build/head_offsets/test.log'))
 if($LASTEXITCODE -or $log -notmatch 'PASS tb_yunet_head_offsets' -or $log -notmatch 'Errors: 0, Warnings: 0'){throw 'scanner/decoder integration failed'}
}finally{Pop-Location}
