param([switch]$SkipFullFrame)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $root
try {
 & scripts/run_axi_checks.ps1
 & scripts/run_flicker_checks.ps1
 & scripts/run_v12_failure_checks.ps1
 & scripts/run_camera_path_checks.ps1 -FullFrame:(!$SkipFullFrame)
 if(-not $SkipFullFrame){
  $lib=Join-Path $root 'sim/work_axi_fix'
  & vlog.exe -sv -work $lib rtl/platform/ddr_user_arbiter.v user_source/hdl_source/video_in.v user_source/hdl_source/video_out.v user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v sim/tb_frame_loop_abcd.v *> sim/frame_loop_axi_compile.log
  if($LASTEXITCODE){throw 'Full-frame compilation failed'}
  & vsim.exe -c -lib $lib tb_frame_loop_abcd -gSTALL_MC=1 -l sim/tb_frame_loop_abcd_axi_stall.log -do 'run -all; quit -code 0' *> sim/frame_loop_axi_console.log
  $result=Get-Content sim/tb_frame_loop_abcd_axi_stall.log -Raw
  if($LASTEXITCODE -or $result -notmatch 'PASS tb_frame_loop_abcd' -or $result -match '\*\* Error|\*\* Fatal|\$fatal'){throw 'Full-frame simulation failed'}
  Write-Output 'PASS full 1280x720 frame loop with MC stalls'
 }
 if($SkipFullFrame){Write-Output 'Quick checks passed; full-frame gate has NOT run.'}
 else{Write-Output 'Display preflight passed, including full-frame gate.'}
 Write-Output 'No TD build or programming was started.'
} finally {Pop-Location}
