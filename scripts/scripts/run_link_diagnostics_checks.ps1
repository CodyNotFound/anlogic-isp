param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $root
try {
 $lib='sim/work_v28';$hud='sim/work_v28_hud'
 foreach($l in @($lib,$hud)){if(-not(Test-Path $l)){& vlib.exe $l;if($LASTEXITCODE){throw 'vlib failed'}}}
 $sources=@('rtl/app/video_link_monitor.v','user_source/hdl_source/isp/csi_unpacket_2lane.v','user_source/hdl_source/isp/raw10_unpacket_2lane.v','user_source/hdl_source/video_in.v','user_source/hdl_source/video_out.v','user_source/hdl_source/mc_to_user_interface.v','user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v','user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v','user_source/ip_source/w155_d512_fifo/w155_d512_fifo.v','user_source/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v','sim/tb_csi_raw10_order.v','sim/tb_video_link_monitor.v','sim/tb_live_frame_transport.v')
 & vlog.exe -sv -work $lib @sources *> sim/link_diagnostics_compile.log
 if($LASTEXITCODE){throw 'Link diagnostics compile failed'}
 & vlog.exe -sv -work $hud user_source/hdl_source/hdmi_mixer.v sim/osd_rom_real_models.v sim/tb_error_hud.v *> sim/error_hud_compile.log
 if($LASTEXITCODE){throw 'HUD compile failed'}
 foreach($test in @('tb_csi_raw10_order','tb_video_link_monitor','tb_live_frame_transport','tb_error_hud')){
  $work=if($test -eq 'tb_error_hud'){'work_v28_hud'}else{'work_v28'}
  Push-Location sim
  try {
   & vsim.exe -c -lib $work $test -l "$test.log" -do 'run -all; quit -code 0' *> "$test.console.log"
   $log=Get-Content "$test.log" -Raw
   if($LASTEXITCODE -or $log -notmatch "PASS $test" -or $log -match '\*\* Error|\*\* Fatal|\$fatal|FAIL'){throw "Failed $test"}
  }finally{Pop-Location}
  Write-Output "PASS $test"
 }
}finally{Pop-Location}
