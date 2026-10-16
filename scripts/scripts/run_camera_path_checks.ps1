param([switch]$FullFrame)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Assert-Sim([string]$Log,[string]$Pass){
 $result=Get-Content -LiteralPath $Log -Raw
 if($LASTEXITCODE -or $result -notmatch $Pass -or $result -match '\*\* Error|\*\* Fatal|\$fatal|FAIL'){throw "Simulation failed: $Log"}
}
Push-Location $root
try {
 # This also compiles the actual ISP, generated RAM/FIFO, and TD primitives.
 & scripts/run_frame_preamble_sim.ps1 -FullFrame:$FullFrame *> sim/camera_path_setup.log
 if(-not $?) {throw 'ISP setup/preamble regression failed'}
 & vlog.exe -sv -work sim/work rtl/platform/ddr_user_arbiter.v user_source/hdl_source/video_out.v user_source/hdl_source/mc_to_user_interface.v user_source/ip_source/w155_d512_fifo/w155_d512_fifo.v user_source/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v sim/tb_demosaic_boundary.v sim/tb_isp_pixel_order.v sim/tb_camera_display_order.v *> sim/camera_path_compile.log
 if($LASTEXITCODE){throw 'Camera path compile failed'}
 Push-Location sim
 try{
  foreach($test in @('tb_isp_pixel_order','tb_camera_display_order','tb_demosaic_boundary')){
   $extra=@();$pass="PASS $test"
   if($test -eq 'tb_demosaic_boundary'){$extra=@('-gCHECK_FIRST=1','-gREAL_CADENCE=1','-gVECTOR_TEST=1');$pass='PASS boundary verification'}
   $log="$test`_camera_path.log"
   & vsim.exe -c -lib work $test PH1P_PHY_GSR @extra -l $log -do 'run -all; quit -code 0' *> "$test`_camera_console.log"
   Assert-Sim $log $pass
   Write-Output "PASS $test"
  }
 }finally{Pop-Location}
 $lib='sim/work_ab_placement'
 if(-not(Test-Path $lib)){& vlib.exe $lib;if($LASTEXITCODE){throw 'vlib failed'}}
 & vlog.exe -sv -work $lib +incdir+rtl/app rtl/app/vision_pipeline.v rtl/control/mode_ctrl.v rtl/control/switch_ctrl.v rtl/isp/auto_exposure.v rtl/isp/auto_white_balance.v rtl/isp/histogram_equalizer.v rtl/isp/pixel_algorithm.v rtl/overlay/adaptive_brightness.v user_source/hdl_source/hdmi_mixer.v sim/osd_rom_real_models.v sim/tb_ab_before_osd.v *> sim/ab_placement_compile.log
 if($LASTEXITCODE){throw 'AB placement compile failed'}
 Push-Location sim
 try{
  & vsim.exe -c -lib work_ab_placement tb_ab_before_osd -l tb_ab_before_osd.log -do 'run -all; quit -code 0' *> ab_placement_console.log
  Assert-Sim tb_ab_before_osd.log 'PASS tb_ab_before_osd'
  Write-Output 'PASS tb_ab_before_osd'
 }finally{Pop-Location}
} finally{Pop-Location}
