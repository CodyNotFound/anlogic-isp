param([string]$PlatformRoot='', [switch]$FullFrame)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'sim_common.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $PlatformRoot){$PlatformRoot=$root}
$PlatformRoot=[IO.Path]::GetFullPath($PlatformRoot)
$sim=Join-Path $root 'sim'
$tdRoot=Split-Path (Split-Path (Get-Command td_commands_prompt.exe -ErrorAction Stop).Source)
$d=Join-Path $PlatformRoot 'rtl/hardware/hdl_source/isp/demosaic_4x_2_0'
$sources=@(
 "$root/rtl/common/reset_sync.v",
 (Join-Path $tdRoot 'sim_release/ph1p/ph1p_phy_gsr.v'),
 (Join-Path $tdRoot 'sim_release/ph1p/ph1p_logic_eram.v'),
 "$d/blk_mem_gen_zhenghe/RTL/ram_d32970204f32.v",
 "$d/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.v",
 "$d/blk_mem_gen_demosaic/RTL/ram_c36c2ca3b3a7.v",
 "$d/blk_mem_gen_demosaic/blk_mem_gen_demosaic.v",
 "$d/mipi_to_raw_converter.v", "$root/rtl/hardware/hdl_source/isp/demosaic_4x_2_0/zhenghe.v", "$root/rtl/hardware/hdl_source/isp/demosaic_4x_2_0/line_buffer_demosaic.v",
 "$root/rtl/hardware/hdl_source/isp/demosaic_4x_2_0/raw_matrix_3x3_buffer.v", "$d/bilinear_interpolation.v", "$d/demosaic.v",
 "$PlatformRoot/rtl/hardware/hdl_source/isp/data128_96/data128_96.v",
 "$PlatformRoot/rtl/hardware/hdl_source/isp/data96_128/data96_128.v",
 "$PlatformRoot/rtl/hardware/hdl_source/video_in.v",
 "$PlatformRoot/rtl/hardware/ip_source/w128_d512_fifo/w128_d512_fifo.v",
 "$PlatformRoot/rtl/hardware/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v",
 "$root/rtl/isp/raw_lsc_grid4.v", "$root/rtl/isp/frame_awb4.v", "$root/rtl/isp/switchable_awb4.v", "$root/rtl/isp/color_tone4.v",
 "$root/rtl/control/vision_demo_cdc.v",
 "$root/rtl/hardware/hdl_source/isp/isp_top.v",
 "$sim/tb_video_in_frame_preamble.v", "$sim/tb_isp_frame_preamble.v"
)
foreach($source in $sources){if(-not(Test-Path -LiteralPath $source)){throw "Missing source: $source"}}
foreach($top in @('tb_video_in_frame_preamble','tb_isp_frame_preamble')){
 $parameters=if($FullFrame -and $top -eq 'tb_isp_frame_preamble'){@('-gLINES_PER_FRAME=720')}else{@()}
 Invoke-RtlTest -Name $top -Top $top -Files $sources -Includes @('rtl/isp') -ExtraTops @('PH1P_PHY_GSR') -Parameters $parameters -AllowVendorModelWarnings
}
