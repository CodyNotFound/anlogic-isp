param([Parameter(Mandatory=$true)][string]$RunName,[Parameter(Mandatory=$true)][ValidateSet('original_motion','slim32_motion')][string]$Label)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$delivery='[LOCAL_PATH]'
$utf8=[Text.UTF8Encoding]::new($false)
$python="$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
$expected=(Get-FileHash (Join-Path $root 'rtl/analytics/face_cnn/program.hex') -Algorithm SHA256).Hash
$statusPath=Join-Path $root "build/verification/${Label}_delivery.json"
$history=@();$current=$RunName
function Save-State($status,$message){
 $record=[ordered]@{label=$Label;status=$status;run=$current;updated_utc=[DateTime]::UtcNow.ToString('o');message=$message;attempts=$history}
 [IO.File]::WriteAllText($statusPath,($record|ConvertTo-Json -Depth 8),$utf8)
}
try{
 foreach($ripple in @(16,24,32)){
  if($ripple -ne 16){
   $current=$RunName -replace 'ripple16$',("ripple"+$ripple)
   if((Get-FileHash (Join-Path $root 'rtl/analytics/face_cnn/program.hex') -Algorithm SHA256).Hash -ne $expected){throw 'Model changed during candidate search'}
   Save-State 'building' "Retry with min_ripple_len=$ripple; source files unchanged"
   try{& (Join-Path $root 'scripts/build_verified.ps1') -RunName $current -DisableFsmInference -AllowSlicePackingProbe -MinRippleLength $ripple}catch{Write-Output $_.Exception.Message}
  }
  $jobPath=Join-Path $root "build/verification/${current}_job.json"
  Save-State 'waiting' 'Waiting for build and final routed audit'
  do{
   Start-Sleep -Seconds 10
   if(!(Test-Path $jobPath)){continue}
   $job=Get-Content $jobPath -Raw|ConvertFrom-Json
  }while($null -eq $job -or $job.status -eq 'running')
  $history+=@([ordered]@{run=$current;status=$job.status;error=$job.error;ripple=$ripple})
  if($job.status -eq 'passed'){
   $heads=Join-Path $root 'build/head_offsets/test.log'
   if(!(Test-Path $heads) -or [IO.File]::ReadAllText($heads) -notmatch 'PASS tb_yunet_head_offsets'){throw 'Head scanner regression evidence missing'}
   $network=if($Label -eq 'slim32_motion'){Join-Path $root 'reports/cnn_v74/test.log'}else{Join-Path $root 'build/cnn_lossless_pack_trial/test.log'}
   if(!(Test-Path $network) -or [IO.File]::ReadAllText($network) -notmatch 'PASS tb_yunet_network_v73' -or [IO.File]::ReadAllText($network) -notmatch 'Errors: 0, Warnings: 0'){throw 'Full network regression evidence missing or failed'}
   Push-Location $root
   try{& $python scripts/archive_build.py $current;if($LASTEXITCODE){throw 'Archive failed'}}finally{Pop-Location}
   $completion=Join-Path $root "build/verification/${current}_completion.json"
   $result=Get-Content $completion -Raw|ConvertFrom-Json
   New-Item -ItemType Directory -Force $delivery | Out-Null
   $bit=Join-Path $delivery ($Label+'.bit')
   if(Test-Path $bit){throw 'Refusing to overwrite a retained test bit'}
   Copy-Item -LiteralPath $result.bit_path -Destination $bit
   if((Get-FileHash $bit -Algorithm SHA256).Hash -ne $result.bit_sha256){throw 'Delivery bit checksum mismatch'}
   Copy-Item $completion (Join-Path $delivery ($Label+'_completion.json'))
   Copy-Item $heads (Join-Path $delivery ($Label+'_head_scanner.log'))
   Copy-Item $network (Join-Path $delivery ($Label+'_network.log'))
   $manifest=[ordered]@{label=$Label;bit=$bit;sha256=$result.bit_sha256;model_program_sha256=$expected;run=$current;archive=(Join-Path $root "releases/$current");board_validated=$false;model_accuracy=if($Label -eq 'slim32_motion'){'Experimental slim32 v2: offline precision regression; requires false-lock testing'}else{'Original production model plus experimental motion assistance'};attempts=$history}
   [IO.File]::WriteAllText((Join-Path $delivery ($Label+'_manifest.json')),($manifest|ConvertTo-Json -Depth 8),$utf8)
   Save-State 'delivered' $bit
   exit 0
  }
  if($job.error -notmatch 'slice number|Resource exceeds|Final setup/hold timing'){throw "Non-timing/resource build failure: $($job.error)"}
  $job=$null
 }
 throw 'All three arithmetic mapping candidates failed; no passing test bit released'
}catch{Save-State 'failed' $_.Exception.Message;throw}
