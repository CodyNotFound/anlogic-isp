$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'sim_common.ps1')
$files=@('rtl/hardware/hdl_source/mc_to_user_interface.v','sim/mc_to_user_interface_v9_reference.v','rtl/hardware/ip_source/w155_d512_fifo/w155_d512_fifo.v','rtl/hardware/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v','sim/tb_mc_command_handshake.v','sim/tb_mc_axi_backpressure.v')
foreach($top in @('tb_mc_command_handshake','tb_mc_axi_backpressure')){Invoke-RtlTest -Name $top -Top $top -Files $files -AllowVendorModelWarnings}
