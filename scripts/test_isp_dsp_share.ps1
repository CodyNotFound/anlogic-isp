$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'sim_common.ps1')
$files=@('rtl/isp/frame_awb4.v','rtl/isp/raw_lsc_grid4.v','sim/reference/frame_awb4_throughput_ref.v','sim/reference/raw_lsc_grid4_throughput_ref.v','sim/isp/tb_isp_dsp_share.sv')
foreach($top in @('tb_awb_dsp_share','tb_lsc_dsp_share')){Invoke-RtlTest -Name $top -Top $top -Files $files -Includes @('rtl/isp')}
