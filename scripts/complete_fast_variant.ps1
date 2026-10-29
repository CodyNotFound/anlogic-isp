param([Parameter(Mandatory=$true)][string]$RunName)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$label='original150_motion_nohmi'
$out=Join-Path $root 'build/verification'
$statusPath=Join-Path $out ($label+'_delivery.json')
$utf8=[Text.UTF8Encoding]::new($false)
function Save-State($status,$message){[IO.File]::WriteAllText($statusPath,([ordered]@{status=$status;run=$RunName;message=$message;updated_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),$utf8)}
try{
 Save-State 'waiting' 'Waiting for routed whole-board timing and exact functional regressions'
 $jobPath=Join-Path $out ($RunName+'_job.json')
 do{
  Start-Sleep -Seconds 10
  if(!(Test-Path $jobPath)){continue}
  $job=Get-Content $jobPath -Raw|ConvertFrom-Json
  if($job.status -eq 'failed'){throw $job.error}
  $networkPath=Join-Path $root 'build/fast_network_dual/test.log'
  if(Test-Path $networkPath){$log=Get-Content -LiteralPath $networkPath -Raw;if($log -match '(?m)^# \*\* (Fatal|Error):'){throw 'Dual-clock full network regression failed'}}
  $suitePath=Join-Path $root 'build/dual_clock/completion.json'
 }while($job.status -ne 'passed' -or !(Test-Path $suitePath) -or $log -notmatch 'PASS tb_yunet_network_fast: all 55 operations' -or $log -notmatch 'Errors: 0, Warnings: 0')
 $suite=Get-Content $suitePath -Raw|ConvertFrom-Json
 if($suite.status -ne 'passed' -or $suite.tests.Count -ne 6){throw 'Six dual-clock application regressions required'}
 $snapshots=@($suite.source_sha256)+@(Get-Content (Join-Path $root 'build/fast_network_dual/sources.json') -Raw|ConvertFrom-Json)
 foreach($item in $snapshots){if((Get-FileHash (Join-Path $root $item.path) -Algorithm SHA256).Hash -ne $item.sha256){throw ('Regression source changed: '+$item.path)}}
 $top=[IO.File]::ReadAllText((Join-Path $root 'rtl/app/design_top_wrapper.v'))
 if(!$top.Contains('.ENABLE_HMI(0)') -or !$top.Contains('.FACE_CORE_CLK_X2(1)')){throw 'Expected local-only 150MHz top configuration'}
 $m=[regex]::Match($log,'all 55 operations, 659460 exact activation bytes, (\d+) cycles')
 if(!$m.Success){throw 'Full graph cycle count missing'}
 $cycles=[long]$m.Groups[1].Value
 $python="$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
 Push-Location $root
 try{& $python scripts/archive_build.py $RunName;if($LASTEXITCODE){throw 'Verified archive failed'}}finally{Pop-Location}
 $completionPath=Join-Path $out ($RunName+'_completion.json');$completion=Get-Content $completionPath -Raw|ConvertFrom-Json
 $delivery='[LOCAL_PATH]';New-Item -ItemType Directory -Force $delivery|Out-Null
 $bit=Join-Path $delivery ($label+'.bit');if(Test-Path $bit){throw 'Refusing to overwrite retained bit'}
 Copy-Item -LiteralPath $completion.bit_path -Destination $bit
 if((Get-FileHash $bit -Algorithm SHA256).Hash -ne $completion.bit_sha256){throw 'Bit checksum mismatch'}
 Copy-Item $completionPath (Join-Path $delivery ($label+'_completion.json'))
 Copy-Item $networkPath (Join-Path $delivery ($label+'_network.log'))
 Copy-Item $suitePath (Join-Path $delivery ($label+'_functional.json'))
 $manifest=[ordered]@{label=$label;run=$RunName;bit=$bit;sha256=$completion.bit_sha256;core_clock_mhz=150;video_clock_mhz=75;serial_hmi=$false;model='Original production YuNet';exact_activation_bytes=659460;compute_cycles=$cycles;compute_ms=($cycles/150000.0);board_validated=$false}
 [IO.File]::WriteAllText((Join-Path $delivery ($label+'_manifest.json')),($manifest|ConvertTo-Json),$utf8)
 Save-State 'delivered' $bit
}catch{Save-State 'failed' $_.Exception.Message;throw}