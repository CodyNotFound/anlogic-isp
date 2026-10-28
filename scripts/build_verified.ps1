param([string]$RunName=('anlogic-isp_runs_'+(Get-Date -Format 'yyyyMMdd_HHmmss')),
[switch]$DisableFsmInference,
[switch]$AllowSlicePackingProbe)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installedRoot='[LOCAL_PATH]'
if($root -ne $installedRoot -and -not($root.StartsWith(($installedRoot+'\worktrees\'),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath (Join-Path $root '.git') -PathType Leaf))){throw 'Unexpected project/worktree root'}
if($RunName -notmatch '^anlogic-isp_runs_[A-Za-z0-9_]+$'){throw 'Invalid run name'}
$match=[regex]::Match($RunName,'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$');$version=if($match.Success){$match.Groups[1].Value}else{($RunName -split '_')[-1]}
$jobPath=Join-Path $root "build/verification/${version}_job.json"
$utf8=[Text.UTF8Encoding]::new($false)
$job=[ordered]@{status='running';run=$RunName;pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o');stage='Check';completed_utc=$null;error=$null;disable_fsm_inference=[bool]$DisableFsmInference;slice_packing_probe=[bool]$AllowSlicePackingProbe}
function Save-Job{[IO.File]::WriteAllText($jobPath,($job|ConvertTo-Json -Depth 5),$utf8)}
New-Item -ItemType Directory -Force -Path (Split-Path $jobPath) | Out-Null
Save-Job
try{
 foreach($stage in @('Check','Synthesis','Implementation')){
  $job.stage=$stage;Save-Job
  $buildArguments=@{Stage=$stage;RunName=$RunName;AllowGateTimingExploration=$true}
  if($DisableFsmInference){$buildArguments.DisableFsmInference=$true}
  & (Join-Path $root 'scripts/build.ps1') @buildArguments
  if($stage -eq 'Synthesis'){
   $area=[IO.File]::ReadAllText((Join-Path $root "td_project/$RunName/syn/anlogic-isp_gate.area"))
   foreach($limit in @(@('slice\*?',21216),@('eram',108),@('dsp',40),@('used ram',8112))){
    $m=[regex]::Match($area,('(?m)^\s*#'+$limit[0]+'\s+(\d+)'))
    if(-not $m.Success){throw "Missing resource metric: $($limit[0])"}
    if([int]$m.Groups[1].Value -gt $limit[1]){
     if($AllowSlicePackingProbe -and $limit[0] -eq 'slice\*?'){
      Write-Warning "Pre-placement slice estimate $($m.Groups[1].Value) exceeds $($limit[1]); explicitly requested packing probe. Final physical capacity/timing checks still apply."
     }else{throw "Resource exceeds device: $($limit[0])=$($m.Groups[1].Value) limit=$($limit[1])"}
    }
   }
  }
 }
 # Deterministic process completion: no model polling while TD is running.
 & (Join-Path $PSScriptRoot 'verify_build.ps1') -TdProcessId 0 -ProjectRoot $root -RunName $RunName
 $report=Get-Content -LiteralPath (Join-Path $root "build/verification/${version}_completion.json") -Raw|ConvertFrom-Json
 $job.status=$report.status
 if($report.status -ne 'passed'){$job.error=$report.errors -join '; '}
}catch{
 $job.status='failed';$job.error=$_.Exception.Message
}finally{
 $job.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Job
 # Keep v*_job.json in colorshading; obsolete stage sync disabled.
}
if($job.status -ne 'passed'){throw "Build failed: $($job.error)"}
