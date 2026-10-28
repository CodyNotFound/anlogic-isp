param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lib=Join-Path $root 'sim/work_axi_fix'
if(-not(Test-Path -LiteralPath $lib)){& vlib.exe $lib;if($LASTEXITCODE){throw 'vlib failed'}}
$sources=@('rtl/hardware/hdl_source/mc_to_user_interface.v','sim/mc_to_user_interface_v9_reference.v','rtl/hardware/ip_source/w155_d512_fifo/w155_d512_fifo.v','rtl/hardware/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v','sim/tb_mc_command_handshake.v','sim/tb_mc_axi_backpressure.v') | ForEach-Object {Join-Path $root $_}
& vlog.exe -sv -work $lib @sources *> (Join-Path $root 'sim/axi_fix_compile.log')
if($LASTEXITCODE){throw 'AXI regression compile failed'}
foreach($test in @('tb_mc_command_handshake','tb_mc_axi_backpressure')){
 $log=Join-Path $root "sim/$test.log"
 & vsim.exe -c -lib $lib $test -l $log -do 'run -all; quit -code 0' | Out-Null
 $result=Get-Content -LiteralPath $log -Raw
 if($LASTEXITCODE -or $result -notmatch "PASS $test" -or $result -match '\*\* Error|\*\* Fatal|\$fatal|FAIL'){throw "Failed $test; see $log"}
 Write-Output "PASS $test"
}
