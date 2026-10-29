param([string]$RunName='anlogic-isp_runs_20261029_cnn_area_next_r1_ripple24')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$statusPath=Join-Path $root "build/verification/${RunName}_job.json"
$state=[ordered]@{status='running';run=$RunName;pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o');stage='Check';completed_utc=$null;error=$null}
function Save-State{[IO.File]::WriteAllText($statusPath,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
try{
 foreach($phase in @('Check','Synthesis')){
  $state.stage=$phase;Save-State
  & (Join-Path $PSScriptRoot 'build.ps1') -Stage $phase -RunName $RunName -DisableFsmInference -MinRippleLength 24 -AllowGateTimingExploration
 }
 $state.status='synthesis_complete'
}catch{$state.status='failed';$state.error=$_.Exception.Message;throw}
finally{$state.completed_utc=[DateTime]::UtcNow.ToString('o');Save-State}