param([string]$Destination='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$stage=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
if($target -ne '[LOCAL_PATH]'){throw 'Unexpected installation target'}
$plan=Get-Content -LiteralPath (Join-Path $stage 'doc/compile/osd_port_install_plan.json') -Raw|ConvertFrom-Json
$backupRoot=Join-Path $target 'doc/rollback/colorshading_osd_port_20261014'
foreach($entry in $plan){
 $dest=[IO.Path]::GetFullPath((Join-Path $target $entry.path))
 if(-not $dest.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target escaped project'}
 $source=Join-Path $stage $entry.path
 if(-not(Test-Path -LiteralPath $source)){throw "Missing staged source: $($entry.path)"}
 if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256){throw "Staged source changed: $($entry.path)"}
 $current=if(Test-Path -LiteralPath $dest){(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash}else{$null}
 if($current -ne $entry.previous_sha256){throw "Target changed since review: $($entry.path)"}
 if($null -ne $current -and (Test-Path -LiteralPath (Join-Path $backupRoot $entry.path))){throw "Existing rollback copy: $($entry.path)"}
}
foreach($entry in $plan){
 $dest=Join-Path $target $entry.path
 if(Test-Path -LiteralPath $dest){
  $backup=Join-Path $backupRoot $entry.path
  New-Item -ItemType Directory -Force -Path (Split-Path $backup)|Out-Null
  Copy-Item -LiteralPath $dest -Destination $backup
 }
 New-Item -ItemType Directory -Force -Path (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath (Join-Path $stage $entry.path) -Destination $dest -Force
 if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $entry.sha256){throw "Installed hash mismatch: $($entry.path)"}
}
Copy-Item -LiteralPath (Join-Path $stage 'doc/compile/osd_port_install_plan.json') -Destination (Join-Path $target 'doc/compile/osd_port_install_plan.json') -Force
Copy-Item -LiteralPath (Join-Path $stage 'install_manifest.json') -Destination (Join-Path $target 'doc/compile/install_manifest.json') -Force
Write-Output "Installed $($plan.Count) reviewed OSD files. Source remains UNBUILT; no TD run, bit generation, or flashing."
