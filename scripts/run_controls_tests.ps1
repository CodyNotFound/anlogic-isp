$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'sim_common.ps1')
$files=Get-ApplicationSimSources
foreach($top in @('tb_local_controls','tb_pipeline_latency')){Invoke-RtlTest -Name $top -Top $top -Files ($files+@("sim/$top.sv")) -Includes @('rtl/app','rtl/analytics/face_cnn')}
