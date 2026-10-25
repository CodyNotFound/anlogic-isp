param([string]$PlatformRoot='', [switch]$FullFrame)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $PlatformRoot){$PlatformRoot=$root}
$PlatformRoot=[IO.Path]::GetFullPath($PlatformRoot)
$sim=Join-Path $root 'sim'
$work=Join-Path $sim 'work'
$modelSimBin=Split-Path (Get-Command vlog.exe -ErrorAction Stop).Source
$tdRoot=Split-Path (Split-Path (Get-Command td_commands_prompt.exe -ErrorAction Stop).Source)
$d=Join-Path $PlatformRoot 'user_source/hdl_source/isp/demosaic_4x_2_0'
$sources=@(
 (Join-Path $tdRoot 'sim_release/ph1p/ph1p_phy_gsr.v'),
 (Join-Path $tdRoot 'sim_release/ph1p/ph1p_logic_eram.v'),
 "$d/blk_mem_gen_zhenghe/RTL/ram_d32970204f32.v",
 "$d/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v",
 "$d/blk_mem_gen_demosaic/RTL/ram_c36c2ca3b3a7.v",
 "$d/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v",
 "$d/mipi_to_raw_converter.v", "$root/user_source/hdl_source/isp/demosaic_4x_2_0/zhenghe.v", "$root/user_source/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v",
 "$root/user_source/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v", "$d/bilinear_interpolation.v", "$d/demosaic.v",
 "$PlatformRoot/user_source/hdl_source/isp/data128_96/data128_96.v",
 "$PlatformRoot/user_source/hdl_source/isp/data96_128/data96_128.v",
 "$PlatformRoot/user_source/hdl_source/video_in.v",
 "$PlatformRoot/user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v",
 "$PlatformRoot/user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v",
 "$root/rtl/isp/raw_lsc_grid4.v", "$root/rtl/isp/frame_awb4.v", "$root/rtl/isp/switchable_awb4.v", "$root/rtl/isp/color_tone4.v",
 "$root/rtl/control/vision_demo_cdc.v",
 "$root/user_source/hdl_source/isp/isp_top.v",
 "$sim/tb_video_in_frame_preamble.v", "$sim/tb_isp_frame_preamble.v"
)
foreach($source in $sources){if(-not(Test-Path -LiteralPath $source)){throw "Missing source: $source"}}
if(-not(Test-Path -LiteralPath $work)){
 & (Join-Path $modelSimBin 'vlib.exe') $work
 if($LASTEXITCODE -ne 0){throw 'vlib failed'}
}
& (Join-Path $modelSimBin 'vlog.exe') -sv -work $work "+incdir+$root/rtl/isp" @sources 2>&1 |
 Tee-Object -FilePath (Join-Path $sim 'frame_preamble_compile.log')
if($LASTEXITCODE -ne 0){throw 'vlog failed'}
foreach($test in @('tb_video_in_frame_preamble','tb_isp_frame_preamble')){
 $simArgs=@('-c','-lib',$work)
 $logName=if($test -eq 'tb_video_in_frame_preamble'){'video_in_frame_preamble_actual_clocks.log'}else{'isp_frame_preamble.log'}
 if($FullFrame -and $test -eq 'tb_isp_frame_preamble'){
  $simArgs+='-gLINES_PER_FRAME=720'; $logName='isp_frame_preamble_720p.log'
 }
 $log=Join-Path $sim $logName
 $simArgs+=@($test,'PH1P_PHY_GSR','-l',$log,'-do','run -all; quit -code 0')
 & (Join-Path $modelSimBin 'vsim.exe') @simArgs
 $result=[IO.File]::ReadAllText($log)
 if($LASTEXITCODE -ne 0 -or $result -notmatch "PASS $test" -or $result -match 'FAIL|\*\* Error|\*\* Fatal'){
  throw "Simulation failed: $test, see $log"
 }
}
