param(
 [Parameter(Mandatory=$true)][int]$TdProcessId,
 [string]$ProjectRoot='[LOCAL_PATH]',
 [string]$RunName=('anlogic-isp_runs_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
)
$ErrorActionPreference='Stop'
$ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot)
$installedRoot='[LOCAL_PATH]'
if($ProjectRoot -ne $installedRoot -and -not($ProjectRoot.StartsWith(($installedRoot+'\worktrees\'),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git') -PathType Leaf))){throw 'Unexpected project/worktree root'}
if($RunName -notmatch '^anlogic-isp_runs_[A-Za-z0-9_]+$'){throw 'Invalid run name'}
$run=Join-Path $ProjectRoot "td_project/$RunName"
$match=[regex]::Match($RunName,'_(v[0-9]+(?:_[A-Za-z0-9_]+)?)$');$version=$RunName
$phy=Join-Path $run 'phy'
$compile=Join-Path $ProjectRoot 'build/verification'
New-Item -ItemType Directory -Force -Path $compile | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
# Native process-completion wait: no timer, progress polling, or model calls.
$process=Get-Process -Id $TdProcessId -ErrorAction SilentlyContinue
if($process -and $process.ProcessName -eq 'td_commands_prompt'){Wait-Process -InputObject $process -ErrorAction SilentlyContinue}
$errors=[Collections.Generic.List[string]]::new()
$result=[ordered]@{
 status='checking'; completed_utc=[DateTime]::UtcNow.ToString('o'); run=$RunName
 process_id=$TdProcessId; setup_wns_ns=$null; setup_tns_ns=$null
 hold_wns_ns=$null; hold_tns_ns=$null; slices=$null; ram=$null; dsp=$null; memory_slices=$null
 source_files_checked=0; bit_path=(Join-Path $phy 'anlogic-isp.bit')
 bit_bytes=0; bit_sha256=$null; sta_coverage_percent=$null; errors=@()
}
try{
 foreach($marker in @('.opt_place.end.f','.opt_route.end.f','.bitgen.end.f')){
  if(-not(Test-Path -LiteralPath (Join-Path $phy $marker))){$errors.Add("Missing success marker: $marker")}
 }
 $routedReport=Join-Path $phy 'anlogic-isp_pr.timing'
 if(Test-Path -LiteralPath $routedReport){
  $routedText=[IO.File]::ReadAllText($routedReport)
  $coverage=[regex]::Match($routedText,'STA coverage\s*:\s*([0-9.]+)%')
  if($coverage.Success){$result.sta_coverage_percent=[double]::Parse($coverage.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)}else{$errors.Add('STA coverage missing')}
  if(-not(Test-Path -LiteralPath (Join-Path $phy 'anlogic-isp_exception.timing'))){$errors.Add('Routed exception report missing')}
  if($routedText -notmatch 'Confidence\s*:\s*Routed'){$errors.Add('Detailed timing report is not routed')}
  else{Copy-Item -LiteralPath $routedReport -Destination (Join-Path $phy 'final_timing.rpt') -Force}
 }else{$errors.Add('Detailed routed timing report missing')}
 $timingFile=Join-Path $phy 'anlogic-isp_phy.ts'
 if(Test-Path -LiteralPath $timingFile){
  $timing=[IO.File]::ReadAllText($timingFile)
  foreach($pair in @(@('SWNS','setup_wns_ns'),@('STNS','setup_tns_ns'),@('HWNS','hold_wns_ns'),@('HTNS','hold_tns_ns'))){
   $match=[regex]::Match($timing,($pair[0]+':\s*([-0-9.]+)ns'))
   if($match.Success){$result[$pair[1]]=[double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)}
   else{$errors.Add("Missing timing metric: $($pair[0])")}
  }
  if($result.setup_wns_ns -lt 0 -or $result.hold_wns_ns -lt 0 -or $result.setup_tns_ns -ne 0 -or $result.hold_tns_ns -ne 0){$errors.Add('Final setup/hold timing has violations')}
 }else{$errors.Add('Final timing summary missing')}
 $areaFile=Join-Path $phy 'anlogic-isp_phy.area'
 if(Test-Path -LiteralPath $areaFile){
  $area=[IO.File]::ReadAllText($areaFile)
  foreach($pair in @(@('slice','slices'),@('eram','ram'),@('dsp','dsp'),@('used ram','memory_slices'))){
   $match=[regex]::Match($area,('(?m)^\s*#'+$pair[0]+'\s+(\d+)'))
   if($match.Success){$result[$pair[1]]=[int]$match.Groups[1].Value}
  }
 }
 $snapshot=Join-Path $run 'source_sha256.txt'
 if(Test-Path -LiteralPath $snapshot){
  foreach($line in [IO.File]::ReadAllLines($snapshot)){
   $match=[regex]::Match($line,'^([A-Fa-f0-9]{64})\s{2}(.+)$')
   if(-not $match.Success){$errors.Add('Invalid source snapshot line');continue}
   $source=Join-Path $ProjectRoot $match.Groups[2].Value
   if(-not(Test-Path -LiteralPath $source)){$errors.Add("Source missing: $source");continue}
   if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $match.Groups[1].Value){$errors.Add("Source changed after Check: $source")}
   $result.source_files_checked++
  }
 }else{$errors.Add('Source snapshot missing')}
 if($result.source_files_checked -eq 0){$errors.Add('No source files were verified')}
 if($null -eq $result.slices -or $null -eq $result.ram -or $null -eq $result.dsp -or $null -eq $result.memory_slices){$errors.Add('Final resource report is incomplete')}
 elseif($result.slices -gt 21216 -or $result.ram -gt 108 -or $result.dsp -gt 40 -or $result.memory_slices -gt 8112){$errors.Add('Final resource utilization exceeds the device')}
 if(Test-Path -LiteralPath $result.bit_path){
  $result.bit_bytes=(Get-Item -LiteralPath $result.bit_path).Length
  $result.bit_sha256=(Get-FileHash -LiteralPath $result.bit_path -Algorithm SHA256).Hash
  if($result.bit_bytes -eq 0){$errors.Add('Bitstream is empty')}
 }else{$errors.Add('Bitstream missing')}
}catch{$errors.Add($_.Exception.Message)}
$result.status=if($errors.Count -eq 0){'passed'}else{'failed'}
$result.errors=@($errors.ToArray())
$jsonPath=Join-Path $compile ($version+'_completion.json')
$reportPath=Join-Path $compile ($version+'_completion.md')
[IO.File]::WriteAllText($jsonPath,($result|ConvertTo-Json -Depth 6),$utf8)
$lines=@(("# colorshading "+$version+" 完成触发结果"),'',"状态：$($result.status)",
 "最终 STA：SWNS $($result.setup_wns_ns) ns，STNS $($result.setup_tns_ns) ns；HWNS $($result.hold_wns_ns) ns，HTNS $($result.hold_tns_ns) ns。",
 "资源：$($result.slices) slices，$($result.ram) RAM，$($result.dsp)/40 DSP，$($result.memory_slices)/8112 M-Slice。",
 "源快照校验：$($result.source_files_checked) 个文件。",
 "bit：$($result.bit_path)","大小：$($result.bit_bytes) bytes；SHA256：$($result.bit_sha256)。",'',
 '本轮修改与仿真依据以对应版本文档、回归日志和源文件快照为准。',
 '路由STA和资源通过后仍需完成对应功能的板上实测。',
 '未烧录；生成bit不等于板上画面验收。')
if($errors.Count){$lines+=@('','失败原因：')+$errors.ToArray()}
$text=$lines -join [Environment]::NewLine
[IO.File]::WriteAllText($reportPath,$text,$utf8)
$verification=Join-Path $compile 'verification.md'
$previous=if(Test-Path -LiteralPath $verification){[IO.File]::ReadAllText($verification)}else{''}
if($previous -notmatch ("<!-- "+$version+"-completion-trigger -->")){
 [IO.File]::WriteAllText($verification,("<!-- ${version}-completion-trigger -->`r`n"+$text+"`r`n`r`n---`r`n`r`n"+$previous),$utf8)
}
Write-Output ("Build verification: {0}; report: {1}" -f $result.status,$reportPath)
