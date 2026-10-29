param(
 [ValidateSet('all','tone','effects','osd','network','cnn-unit','dual-clock','controls','tracking','reticle','reliability','gimbal','isp','ddr')][string[]]$Tests=@('all'),
 [string]$PythonExe='',
 [switch]$List,[switch]$FullFrame
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common/environment.ps1')

. (Join-Path (Get-RepositoryRoot) 'scripts/simulation/sim_common.ps1')
$root=$script:SimRoot
if(!$PythonExe){$PythonExe=Get-ProjectPython}
$groups=@('tone','effects','osd','cnn-unit','network','dual-clock','controls','tracking','reticle','reliability','gimbal','isp','ddr')
if($List){$groups;return}
if($Tests -contains 'all'){$Tests=$groups}
$cnn=@('rtl/analytics/face_cnn/yunet_dot4.v','rtl/analytics/face_cnn/yunet_network.v')
$inc=@('rtl/analytics/face_cnn')
Push-Location $root
try{
 if(@($Tests|Where-Object {$_ -in 'network','cnn-unit','dual-clock','tracking','controls'}).Count){
  & $PythonExe scripts/cnn/check_yunet_dw_bounds.py --bits 18;if($LASTEXITCODE){throw 'Accumulator bounds failed'}
  & $PythonExe scripts/cnn/pack_yunet_rom.py --check;if($LASTEXITCODE){throw 'Packed model constants mismatch'}
 }
 if($Tests -contains 'tone'){Invoke-RtlTest -Name tone -Top tb_color_tone_luma -Files @('rtl/isp/color_tone4.v','sim/reference/color_tone4_before_luma.v','sim/isp/tb_color_tone_luma.sv') -Includes @('rtl/isp')}
 if($Tests -contains 'effects'){Invoke-RtlTest -Name effects -Top tb_pixel_cartoon_timing -Files @('rtl/isp/pixel_cartoon.v','sim/reference/pixel_cartoon_timing_ref.v','sim/isp/tb_pixel_cartoon_timing.sv')}
 if($Tests -contains 'osd'){
  New-Item -ItemType Directory -Force .agent/build/sim/osd|Out-Null
  Invoke-RtlTest -Name osd -Top tb_osd -Files @('rtl/hardware/hdl_source/hdmi_mixer.v','sim/osd/osd_rom_full_models.v','sim/osd/tb_osd.sv') -Cwd $root
  & $PythonExe scripts/simulation/check_osd.py;if($LASTEXITCODE){throw 'OSD pixel references differ'}
 }
 if($Tests -contains 'cnn-unit'){
  foreach($top in @('tb_yunet_rom_unpack','tb_yunet_address_exact','tb_yunet_dw18_quant','tb_yunet_fast_mac','tb_yunet_mac20','tb_yunet_vector_misc')){
   $files=if($top -eq 'tb_yunet_rom_unpack'){@()}elseif($top -in 'tb_yunet_fast_mac','tb_yunet_mac20'){@($cnn[0])}else{$cnn}
   Invoke-RtlTest -Name $top -Top $top -Files (@($files)+@("sim/cnn/$top.sv")) -Includes $inc
  }
  Invoke-RtlTest -Name decoder -Top tb_yunet_decode_timing -Files @('rtl/analytics/face_cnn/yunet_decode.v','sim/reference/yunet_decode_timing_ref.v','sim/cnn/tb_yunet_decode_timing.sv') -Includes $inc
 }
 if($Tests -contains 'network'){Invoke-RtlTest -Name network -Top tb_yunet_network_fast -Files ($cnn+@('sim/cnn/tb_yunet_network_fast.sv')) -Includes $inc}
 if($Tests -contains 'dual-clock'){
  & $PythonExe sim/cnn/check_head_offsets.py;if($LASTEXITCODE){throw 'Head fixture failed'}
  $files=@('rtl/common/reset_sync.v','rtl/analytics/face_cnn/yunet_clock_bridge.v')+$cnn+@('rtl/analytics/face_cnn/yunet_decode.v','rtl/analytics/face_cnn/yunet_position_snapshot.v','rtl/analytics/face_cnn/yunet_rgb_snapshot.v','rtl/analytics/face_cnn/face_video_cnn.v','rtl/analytics/vision_tasks/vision_sad_tracker.v','rtl/analytics/vision_tasks/vision_motion_diff.v','rtl/analytics/vision_tasks/vision_unsigned_divider.v','rtl/analytics/vision_tasks/vision_color_region.v')
  foreach($top in @('tb_yunet_clock_bridge','tb_yunet_dual_arena','tb_yunet_dual_heads','tb_yunet_dual_motion','tb_yunet_dual_color','tb_yunet_dual_tracker')){Invoke-RtlTest -Name $top -Top $top -Files (@($files)+@("sim/cnn/$top.sv")) -Includes $inc}
 }
 if($Tests -contains 'controls'){& ./scripts/simulation/run_controls_tests.ps1}
 if($Tests -contains 'tracking'){& ./scripts/simulation/run_tracking_tests.ps1}
 if($Tests -contains 'reticle'){Invoke-RtlTest -Name reticle -Top tb_region_reticle -Files @('rtl/analytics/vision_tasks/vision_bcd.v','rtl/analytics/vision_tasks/vision_task_hud.v','sim/tracking/tb_region_reticle.sv')}
 if($Tests -contains 'reliability'){
  Invoke-RtlTest -Name i2c -Top tb_i2c_clock_enable -Files @('rtl/common/reset_sync.v','rtl/hardware/hdl_source/uics500_cfg/uii2c.v','sim/reference/uii2c_divided_reference.v','sim/control/tb_i2c_clock_enable.sv')
  foreach($top in @('tb_reset_ae_cdc','tb_model_shift')){Invoke-RtlTest -Name $top -Top $top -Files @('rtl/common/reset_sync.v','rtl/common/frame_stat_cdc.v','rtl/isp/auto_exposure.v','rtl/analytics/face_cnn/yunet_dot4.v','sim/control/tb_reliability.sv')}
 }
 if($Tests -contains 'gimbal'){Invoke-RtlTest -Name gimbal -Top tb_gimbal_equivalence -Files @('rtl/control/servo_gimbal_ctrl.v','sim/reference/servo_gimbal_reference.v','sim/control/tb_gimbal_equivalence.sv')}
 if($Tests -contains 'isp'){& ./scripts/simulation/test_isp_dsp_share.ps1;& ./scripts/simulation/run_isp_tests.ps1 -FullFrame:$FullFrame}
 if($Tests -contains 'ddr'){& ./scripts/simulation/run_ddr_tests.ps1}
}finally{Pop-Location}
