param([string]$PythonExe="$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));Push-Location $root
try{
 & $PythonExe scripts/pack_yunet_rom.py --check;if($LASTEXITCODE){throw 'model contract failed'}
 $out=Join-Path $root 'build/fast_network';New-Item -ItemType Directory -Force $out|Out-Null
 $bin='[LOCAL_PATH]';$work=Join-Path $out 'work'
 if(!(Test-Path $work)){& "$bin/vlib.exe" $work}
 & "$bin/vlog.exe" -sv +incdir+rtl/analytics/face_cnn -work $work rtl/analytics/face_cnn/yunet_dot4.v rtl/analytics/face_cnn/yunet_network.v sim/face_cnn/tb_yunet_network_fast.sv *> (Join-Path $out 'compile.log')
 if($LASTEXITCODE){throw 'fast network compile failed'}
 $snapshot=foreach($name in @('rtl/analytics/face_cnn/yunet_dot4.v','rtl/analytics/face_cnn/yunet_network.v','rtl/analytics/face_cnn/program.hex')){[ordered]@{path=$name;sha256=(Get-FileHash (Join-Path $root $name) -Algorithm SHA256).Hash}}
 $snapshot|ConvertTo-Json|Set-Content (Join-Path $out 'sources.json') -Encoding UTF8
 & "$bin/vsim.exe" -c -lib $work tb_yunet_network_fast -l (Join-Path $out 'test.log') -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
 $log=[IO.File]::ReadAllText((Join-Path $out 'test.log'))
 if($log -notmatch 'PASS tb_yunet_network_fast' -or $log -notmatch 'Errors: 0, Warnings: 0'){throw 'fast network regression failed'}
}finally{Pop-Location}
