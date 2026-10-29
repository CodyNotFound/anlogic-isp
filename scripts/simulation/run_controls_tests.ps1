$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/environment.ps1')

. (Join-Path (Get-RepositoryRoot) 'scripts/simulation/sim_common.ps1')
$files=Get-ApplicationSimSources
foreach($top in @('tb_local_controls','tb_pipeline_latency')){Invoke-RtlTest -Name $top -Top $top -Files ($files+@($(if($top -eq 'tb_local_controls'){'sim/control/tb_local_controls.sv'}else{'sim/video/tb_pipeline_latency.sv'}))) -Includes @('rtl/app','rtl/analytics/face_cnn')}
