$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'sim_common.ps1')
$files=@('rtl/common/reset_sync.v')+@(Get-ChildItem (Join-Path $script:SimRoot 'rtl/analytics/vision_tasks'),(Join-Path $script:SimRoot 'rtl/analytics/face_cnn') -Filter '*.v'|ForEach-Object FullName)
foreach($entry in @(@('tb_motion','sim/tb_motion.sv'),@('tb_vision_region_identity','sim/vision_tasks/tb_vision_region_identity.sv'))){Invoke-RtlTest -Name $entry[0] -Top $entry[0] -Files ($files+@($entry[1])) -Includes @('rtl/analytics/face_cnn')}
