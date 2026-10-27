param([string]$ModelSimBin='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sim=Join-Path $root 'sim'
$work=Join-Path $sim 'colorshading_work'
& (Join-Path $ModelSimBin 'vlib.exe') $work
if($LASTEXITCODE -ne 0){throw 'vlib failed'}
$sources=@('raw_lsc_grid4','frame_awb4','color_tone4') | ForEach-Object {Join-Path $root "rtl/isp/$_.v"}
$tests=@('tb_raw_lsc_grid4','tb_frame_awb4','tb_color_tone4')
$testFiles=$tests | ForEach-Object {Join-Path $sim "$_.v"}
& (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work "+incdir+$root/rtl/isp" @sources @testFiles
if($LASTEXITCODE -ne 0){throw 'vlog failed'}
foreach($test in $tests){
    $log=Join-Path $sim "$test.log"
    & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work $test -do 'run -all; quit -code 0' -l $log
    $result=[IO.File]::ReadAllText($log)
    if($LASTEXITCODE -ne 0 -or $result -notmatch 'PASS' -or $result -match 'FAIL|\*\* Error|\*\* Fatal'){
        throw "Simulation failed: $test"
    }
}
