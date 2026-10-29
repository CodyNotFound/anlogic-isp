param([string]$RunName=('anlogic-isp_runs_'+(Get-Date -Format 'yyyyMMdd_HHmmss')),
[switch]$DisableFsmInference,
[switch]$AllowSlicePackingProbe,
[int]$MinRippleLength=-1)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common/environment.ps1')

$root=(Get-RepositoryRoot)
if($RunName -notmatch '^anlogic-isp_runs_[A-Za-z0-9_]+$'){throw 'Invalid run name'}
$match=[regex]::Match($RunName,'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$');$version=$RunName
$jobPath=Join-Path $root ".agent/build/verification/${version}_job.json"
$utf8=[Text.UTF8Encoding]::new($false)
$job=[ordered]@{status='running';run=$RunName;pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o');stage='Check';completed_utc=$null;error=$null;disable_fsm_inference=[bool]$DisableFsmInference;slice_packing_probe=[bool]$AllowSlicePackingProbe;min_ripple_length=$MinRippleLength}
function Save-Job{[IO.File]::WriteAllText($jobPath,($job|ConvertTo-Json -Depth 5),$utf8)}
New-Item -ItemType Directory -Force -Path (Split-Path $jobPath) | Out-Null
Save-Job
try{
 foreach($stage in @('Check','Synthesis','Implementation')){
  $job.stage=$stage;Save-Job
  $buildArguments=@{Stage=$stage;RunName=$RunName;AllowGateTimingExploration=$true}
  if($DisableFsmInference){$buildArguments.DisableFsmInference=$true}
  if($MinRippleLength -ge 0){$buildArguments.MinRippleLength=$MinRippleLength}
  & (Join-Path $root 'scripts/build/build.ps1') @buildArguments
  if($stage -eq 'Synthesis'){
   $area=[IO.File]::ReadAllText((Join-Path $root ".agent/build/td/$RunName/syn/anlogic-isp_gate.area"))
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
 & (Join-Path (Get-RepositoryRoot) 'scripts/build/verify_build.ps1') -TdProcessId 0 -ProjectRoot $root -RunName $RunName
 $report=Get-Content -LiteralPath (Join-Path $root ".agent/build/verification/${version}_completion.json") -Raw|ConvertFrom-Json
 $job.status=$report.status
 if($report.status -ne 'passed'){$job.error=$report.errors -join '; '}
}catch{
 $job.status='failed';$job.error=$_.Exception.Message
 if([string]::IsNullOrWhiteSpace($job.error)){
  $phaseDir=if($job.stage -eq 'Implementation'){'phy'}else{'syn'}
  $phaseLog=Join-Path $root (".agent/build/td/$RunName/$phaseDir/"+$job.stage.ToLower()+'.log')
  if(Test-Path -LiteralPath $phaseLog){
   $tdErrors=[regex]::Matches([IO.File]::ReadAllText($phaseLog),'(?im)^[^\r\n]*\bERROR:[^\r\n]*')
   if($tdErrors.Count){$job.error=$tdErrors[$tdErrors.Count-1].Value.Trim()}
  }
  if([string]::IsNullOrWhiteSpace($job.error)){$job.error="$($job.stage) failed; inspect $phaseLog"}
 }
}finally{
 $job.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Job
 # Keep detailed stage evidence in ignored output.
}
if($job.status -ne 'passed'){throw "Build failed: $($job.error)"}
