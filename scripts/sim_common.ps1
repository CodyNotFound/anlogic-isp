# Shared ModelSim invocation; each test has isolated output and source hashes.
$script:SimRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:SimBin=$env:MODELSIM_BIN
if(!$script:SimBin){
 $vlog=Get-Command vlog.exe -ErrorAction SilentlyContinue
 if($vlog){$script:SimBin=Split-Path $vlog.Source}else{$script:SimBin='[LOCAL_PATH]'}
}
function Test-KnownVendorWarning([string]$Line){
 $rules=@(Get-Content (Join-Path $script:SimRoot 'sim/vendor_fifo_warnings.json') -Raw|ConvertFrom-Json)+@(Get-Content (Join-Path $script:SimRoot 'sim/vendor_isp_warnings.json') -Raw|ConvertFrom-Json)
 $normalized=$Line.Replace('\','/')
 foreach($rule in @($rules|ForEach-Object {$_.files})){
  if($normalized -notmatch ([regex]::Escape($rule.path)+'\(\d+\):')){continue}
  if((Get-FileHash (Join-Path $script:SimRoot $rule.path) -Algorithm SHA256).Hash -ne $rule.sha256){return $false}
  if($normalized -match '\(vsim-3017\).*Too few port connections\. Expected 16, found 14\.') {return $true}
  if($normalized -match "\(vsim-3722\).*Missing connection for port '([^']+)'\." -and $Matches[1] -in $rule.unconnected_ports){return $true}
  if($normalized -match "\(vsim-3015\).*Port size \(1\) does not match connection size \(32\) for port '([^']+)'\." -and $Matches[1] -in $rule.one_bit_width_ports){return $true}
  if($normalized -match "\(vsim-3015\).*Port size \(9\) does not match connection size \(32\) for port '([^']+)'\." -and $Matches[1] -in $rule.address_width_ports){return $true}
  if($normalized -match "\(vsim-3015\).*Port size \(33\) does not match connection size \(32\) for port '([^']+)'\." -and $Matches[1] -in $rule.wide_data_ports){return $true}
 }
 return $false
}
function Invoke-RtlTest {
 param([string]$Name,[string]$Top,[string[]]$Files,[string[]]$Includes=@(),[string]$Cwd=$script:SimRoot,[string[]]$ExtraTops=@(),[string[]]$Parameters=@(),[switch]$AllowVendorModelWarnings)
 $ErrorActionPreference='Stop'
 $out=Join-Path $script:SimRoot "build/sim/$Name";$work=Join-Path $out 'work'
 New-Item -ItemType Directory -Force $out|Out-Null
 $sources=@($Files|ForEach-Object {if([IO.Path]::IsPathRooted($_)){$_}else{Join-Path $script:SimRoot $_}})
 foreach($source in $sources){if(!(Test-Path -LiteralPath $source)){throw "Missing simulation source: $source"}}
 if(!(Test-Path $work)){& "$script:SimBin/vlib.exe" $work|Out-Null;if($LASTEXITCODE){throw 'vlib failed'}}
 $inc=@($Includes|ForEach-Object {'+incdir+'+(Join-Path $script:SimRoot $_)})
 & "$script:SimBin/vlog.exe" -sv @inc -work $work @sources *> (Join-Path $out 'compile.log')
 $compile=[IO.File]::ReadAllText((Join-Path $out 'compile.log'))
 if($LASTEXITCODE -or $compile -notmatch 'Errors: 0, Warnings: 0'){throw "Compile failed or warned: $Name (see $out/compile.log)"}
 $inputs=@($sources)+@(Get-ChildItem (Join-Path $script:SimRoot 'rtl/isp') -Filter '*.vh'|ForEach-Object FullName)
 if($Includes -contains 'rtl/analytics/face_cnn'){
  $inputs+=@(Get-ChildItem (Join-Path $script:SimRoot 'rtl/analytics/face_cnn') -File|Where-Object {$_.Extension -in '.hex','.vh','.lo16','.packed'}|ForEach-Object FullName)
 }
 $inputs+=@(Get-ChildItem (Join-Path $script:SimRoot 'sim') -Recurse -File|Where-Object {$_.Extension -in '.hex','.txt','.json','.png' -and $_.Name -notlike 'vendor_*_warnings.json'}|ForEach-Object FullName)
 if($AllowVendorModelWarnings){$inputs+=@('sim/vendor_fifo_warnings.json','sim/vendor_isp_warnings.json')|ForEach-Object {Join-Path $script:SimRoot $_}}
 $snapshot=@($inputs|Sort-Object -Unique|ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})
 $proof=[ordered]@{status='running';test=$Top;source_sha256=$snapshot}
 $proof|ConvertTo-Json -Depth 6|Set-Content (Join-Path $out 'completion.json') -Encoding UTF8
 Push-Location $Cwd
 try{& "$script:SimBin/vsim.exe" -c -lib $work -wlf (Join-Path $out 'waves.wlf') @Parameters $Top @ExtraTops -l (Join-Path $out 'test.log') -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'|Out-Null;$exitCode=$LASTEXITCODE}finally{Pop-Location}
 $log=[IO.File]::ReadAllText((Join-Path $out 'test.log'))
 $summary=[regex]::Match($log,'Errors: (\d+), Warnings: (\d+)')
 $warnings=@([regex]::Matches($log,'(?m)^# \*\* Warning:[^\r\n]*')|ForEach-Object {$_.Value})
 $warningsOK=$summary.Success -and [int]$summary.Groups[2].Value -eq $warnings.Count
 foreach($warning in $warnings){if(!$AllowVendorModelWarnings -or !(Test-KnownVendorWarning $warning)){$warningsOK=$false}}
 $proof.warning_count=$warnings.Count;$proof.known_vendor_warnings=$warnings
 if($exitCode -or !$summary.Success -or [int]$summary.Groups[1].Value -ne 0 -or !$warningsOK -or $log -notmatch ('PASS '+[regex]::Escape($Top)+'\b')){$proof.status='failed'}else{$proof.status='passed'}
 foreach($source in $snapshot){if((Get-FileHash -LiteralPath $source.path -Algorithm SHA256).Hash -ne $source.sha256){$proof.status='failed'}}
 $proof|ConvertTo-Json -Depth 6|Set-Content (Join-Path $out 'completion.json') -Encoding UTF8
 if($proof.status -ne 'passed'){throw "Regression failed: $Name (see $out/test.log)"}
 Write-Output "PASS $Name ($Top)"
}
function Get-ApplicationSimSources {
 @(Get-ChildItem (Join-Path $script:SimRoot 'rtl') -Recurse -Filter '*.v'|Where-Object {$_.FullName -notmatch '[\\/]rtl[\\/](hardware|vendor)[\\/]'}|ForEach-Object FullName)+@('rtl/hardware/hdl_source/hdmi_mixer.v','sim/osd_rom_sim_models.v')
}
