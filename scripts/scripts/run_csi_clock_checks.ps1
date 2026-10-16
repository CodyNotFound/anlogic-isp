param([switch]$FullFrame)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $root
try {
 # Reuse the real ISP, generated RAM and FIFO library set up by this script.
 & scripts/run_frame_preamble_sim.ps1 *> sim/csi_clock_setup.log
 if(-not $?){throw 'ISP library setup failed'}
 & vlog.exe -sv -work sim/work rtl/platform/camera_raw_clock_bridge.v rtl/platform/ddr_user_arbiter.v user_source/hdl_source/isp/csi_unpacket_2lane.v user_source/hdl_source/isp/raw10_unpacket_2lane.v user_source/hdl_source/isp/uial2axis.v user_source/hdl_source/video_out.v user_source/hdl_source/mc_to_user_interface.v user_source/ip_source/w155_d512_fifo/w155_d512_fifo.v user_source/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v sim/tb_csi_isp_frame_integrity.v sim/tb_csi_framebuffer_integrity.v *> sim/csi_clock_compile.log
 if($LASTEXITCODE){throw 'CSI clock regression compile failed'}
 Push-Location sim
 try {
  $cases=@(
   @('csi_bridge_continuous','tb_csi_isp_frame_integrity','-gUSE_BRIDGE=1'),
   @('csi_bridge_stopped','tb_csi_isp_frame_integrity','-gUSE_BRIDGE=1','-gSTOP_CLOCK=1'),
   @('csi_bridge_algorithms','tb_csi_isp_frame_integrity','-gUSE_BRIDGE=1','-gSTOP_CLOCK=1','-gALGORITHMS=1'),
   @('csi_framebuffer_concurrent','tb_csi_framebuffer_integrity'))
  if($FullFrame){$cases+=,@('csi_bridge_720p','tb_csi_isp_frame_integrity','-gUSE_BRIDGE=1','-gSTOP_CLOCK=1','-gALGORITHMS=1','-gHEIGHT=720','-gFRAMES=2')}
  foreach($case in $cases){
   $log=$case[0]+'.log';$simArgs=@('-c','-lib','work',$case[1],'PH1P_PHY_GSR')
   if($case.Count -gt 2){$simArgs+=$case[2..($case.Count-1)]}
   & vsim.exe @simArgs -l $log -do 'run -all; quit -code 0' *> ($case[0]+'_console.log')
   $result=Get-Content -LiteralPath $log -Raw
   if($LASTEXITCODE -or $result -notmatch ('PASS '+$case[1]) -or $result -match '\*\* Error|\*\* Fatal|\$fatal|BAD '){throw "Failed $log"}
   Write-Output ('PASS '+$case[0])
  }
 }finally{Pop-Location}
}finally{Pop-Location}
