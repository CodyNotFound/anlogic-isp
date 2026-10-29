param([string]$RunName='anlogic-isp_runs_20261029_cnn_vector_r1_ripple24',[string]$RegressionName='vector_fast',[switch]$RequireTimingTests)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$jobPath=Join-Path $root "build/verification/${RunName}_job.json"
$deadline=[DateTime]::UtcNow.AddMinutes(90)
$job=$null
function Save-Job{[IO.File]::WriteAllText($jobPath,($job|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
try{
 while($true){
  if([DateTime]::UtcNow -gt $deadline){throw 'Timed out waiting for synthesis'}
  if(Test-Path $jobPath){
   $job=Get-Content $jobPath -Raw|ConvertFrom-Json
   if($job.status -eq 'failed'){throw $job.error}
   if($job.status -eq 'synthesis_complete'){break}
  }
  Start-Sleep -Seconds 10
 }
 $area=[IO.File]::ReadAllText((Join-Path $root "td_project/$RunName/syn/anlogic-isp_gate.area"))
 foreach($limit in @(@('slice\*?',24000),@('eram',108),@('dsp',40))){
  $m=[regex]::Match($area,('(?m)^\s*#'+$limit[0]+'\s+(\d+)'))
  if(!$m.Success -or [int]$m.Groups[1].Value -gt $limit[1]){throw "Synthesis resource gate failed: $($limit[0])"}
 }
 $job.pid=$PID;$job.status='running';$job.stage='Regression';$job.completed_utc=$null;Save-Job
 while($true){
  if([DateTime]::UtcNow -gt $deadline){throw 'Timed out waiting for exact regressions'}
  $fastPath=Join-Path $root "build/$RegressionName/test.log"
  $dualPath=Join-Path $root 'build/dual_clock/completion.json'
  $exact=$false;$dual=$false
  if(Test-Path $fastPath){
   $log=[IO.File]::ReadAllText($fastPath)
   if($log -match '\*\* Fatal:|Errors: [1-9]'){throw 'Full network regression failed'}
   $exact=$log -match 'all 55 operations, 659460 exact activation bytes' -and $log -match 'Errors: 0, Warnings: 0'
  }
  if($exact){
   $snapshot=Get-Content (Join-Path $root "build/$RegressionName/sources.json") -Raw|ConvertFrom-Json
   foreach($source in $snapshot){
    if((Get-FileHash (Join-Path $root $source.path) -Algorithm SHA256).Hash -ne $source.sha256){throw 'Full regression source changed'}
   }
  }
  if(Test-Path $dualPath){
   $proof=Get-Content $dualPath -Raw|ConvertFrom-Json
   $dual=$proof.status -eq 'passed' -and @($proof.tests).Count -eq 6
   foreach($source in $proof.source_sha256){
    if((Get-FileHash (Join-Path $root $source.path) -Algorithm SHA256).Hash -ne $source.sha256){$dual=$false}
   }
  }
  $timingTests=$true
  if($RequireTimingTests){
   foreach($entry in @(@('decode_timing','tb_yunet_decode_timing'),@('cartoon_timing','tb_pixel_cartoon_timing'))){
    $testLog=Join-Path $root "build/$($entry[0])/test.log"
    if(!(Test-Path $testLog)){$timingTests=$false;continue}
    $content=[IO.File]::ReadAllText($testLog)
    if($content -notmatch ("PASS "+$entry[1]) -or $content -notmatch 'Errors: 0, Warnings: 0'){$timingTests=$false}
   }
  }
  foreach($testLog in @(Get-ChildItem (Join-Path $root 'build/dual_clock') -Filter '*.log' -ErrorAction SilentlyContinue)){
   if([IO.File]::ReadAllText($testLog.FullName) -match '\*\* Fatal:|Errors: [1-9]'){throw 'Dual clock regression failed'}
  }
  if($exact -and $dual -and $timingTests){break}
  Start-Sleep -Seconds 10
 }
 $job.stage='Implementation';Save-Job
 & (Join-Path $PSScriptRoot 'build.ps1') -Stage Implementation -RunName $RunName -DisableFsmInference -MinRippleLength 24 -AllowGateTimingExploration
 & (Join-Path $PSScriptRoot 'verify_build.ps1') -TdProcessId 0 -ProjectRoot $root -RunName $RunName
 $report=Get-Content (Join-Path $root "build/verification/${RunName}_completion.json") -Raw|ConvertFrom-Json
 $job.status=$report.status
 if($report.status -ne 'passed'){$job.error=$report.errors -join '; '}
}catch{
 if($null -ne $job){$job.status='failed';$job.error=$_.Exception.Message}
 throw
}finally{
 if($null -ne $job){$job.completed_utc=[DateTime]::UtcNow.ToString('o');Save-Job}
}