param([string]$PlatformRoot='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sim=Join-Path $root 'sim'
$work=Join-Path $sim 'work'
$tdRoot=Split-Path (Split-Path (Get-Command td_commands_prompt.exe -ErrorAction Stop).Source)
$d=Join-Path $PlatformRoot 'user_source/hdl_source/isp/demosaic_4x_2_0'
$own=Join-Path $root 'user_source/hdl_source/isp/demosaic_4x_2_0'
$sources=@(
 "$tdRoot/sim_release/ph1p/ph1p_phy_gsr.v",
 "$tdRoot/sim_release/ph1p/ph1p_logic_eram.v",
 "$d/blk_mem_gen_zhenghe/RTL/ram_d32970204f32.v",
 "$d/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v",
 "$d/blk_mem_gen_demosaic/RTL/ram_c36c2ca3b3a7.v",
 "$d/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v",
 "$d/mipi_to_raw_converter.v","$own/zhenghe.v","$own/line_buffer_demosaic.v",
 "$own/raw_matrix_3x3_buffer.v","$d/bilinear_interpolation.v","$d/demosaic.v",
 "$PlatformRoot/user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v",
 "$PlatformRoot/user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v",
 "$root/rtl/isp/frame_awb4.v","$root/rtl/isp/switchable_awb4.v",
 "$root/user_source/hdl_source/video_out.v","$sim/video_out_v9_reference.v",
 "$sim/tb_frame_awb4.v","$sim/tb_switchable_awb4.v","$sim/tb_awb_freeze.v",
 "$sim/tb_video_out_credit.v","$sim/tb_demosaic_boundary.v"
)
foreach($source in $sources){if(-not(Test-Path -LiteralPath $source)){throw "Missing source: $source"}}
if(-not(Test-Path -LiteralPath $work)){& vlib.exe $work;if($LASTEXITCODE){throw 'vlib failed'}}
& vlog.exe -sv -work $work @sources *> (Join-Path $sim 'flicker_compile.log')
if($LASTEXITCODE){throw 'vlog failed'}
Push-Location $sim
try{
 foreach($test in @('tb_frame_awb4','tb_switchable_awb4','tb_awb_freeze','tb_video_out_credit','tb_demosaic_boundary')){
  $argsList=@('-c','-lib',$work)
  if($test -eq 'tb_demosaic_boundary'){$argsList+='-gVECTOR_TEST=1'}
  $log=Join-Path $sim ($test+'_flicker_fix.log')
  $argsList+=@($test,'PH1P_PHY_GSR','-l',$log,'-do','run -all; quit -code 0')
  & vsim.exe @argsList | Out-Null
  $text=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -or $text -notmatch 'PASS ' -or $text -match '\*\* Error|\*\* Fatal|FAIL|\*\* Note: \$fatal'){
   throw "Failed focused check: $test; see $log"
  }
  Write-Output "PASS $test"
 }
}finally{Pop-Location}
