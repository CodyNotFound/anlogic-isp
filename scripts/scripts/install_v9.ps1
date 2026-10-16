$ErrorActionPreference='Stop'
$stage=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target='[LOCAL_PATH]'
$plan=Get-Content -LiteralPath (Join-Path $stage 'doc/compile/v9_install_plan.json') -Raw|ConvertFrom-Json
foreach($entry in $plan){
 $dest=[IO.Path]::GetFullPath((Join-Path $target $entry.path))
 if(-not $dest.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target escaped project'}
 $source=Join-Path $stage $entry.path
 if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.sha256){throw "Stage changed: $source"}
 $current=if(Test-Path -LiteralPath $dest){(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash}else{$null}
 if($current -ne $entry.previous_sha256){throw "Target changed since review: $dest"}
}
foreach($entry in $plan){
 $dest=Join-Path $target $entry.path
 if(Test-Path -LiteralPath $dest){
  $backup=Join-Path $target ('doc/rollback/colorshading_v9_20261014/'+$entry.path)
  if(Test-Path -LiteralPath $backup){throw "Existing v9 backup: $backup"}
  New-Item -ItemType Directory -Force -Path (Split-Path $backup)|Out-Null
  Copy-Item -LiteralPath $dest -Destination $backup
 }
 New-Item -ItemType Directory -Force -Path (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath (Join-Path $stage $entry.path) -Destination $dest -Force
 if((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $entry.sha256){throw "Copy mismatch: $dest"}
}
Copy-Item -LiteralPath (Join-Path $stage 'install_manifest.json') -Destination (Join-Path $target 'doc/compile/install_manifest.json') -Force
Write-Output "Installed $($plan.Count) reviewed changed files; rollback preserved."
