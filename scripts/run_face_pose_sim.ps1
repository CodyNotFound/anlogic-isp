param([string]$ModelSimBin='[LOCAL_PATH]',[switch]$SkipPrepare,[string]$Variant='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$python='[LOCAL_PATH]'
if($Variant -and $Variant -notmatch '^[A-Za-z0-9_]+$'){throw 'Invalid variant'}
$suffix=if($Variant){"_$Variant"}else{''}
$reportDir=if($Variant){"reports/face_pose/$Variant"}else{'reports/face_pose'}
$outDir=Join-Path $root $reportDir
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$work=Join-Path $root "sim/face_pose/work$suffix"
Push-Location $root
try {
 if(-not $SkipPrepare){& $python scripts/face_pose_prepare.py;if($LASTEXITCODE){throw 'Pose fixtures failed'}}
 if(-not(Test-Path $work)){& (Join-Path $ModelSimBin 'vlib.exe') $work;if($LASTEXITCODE){throw 'vlib failed'}}
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work rtl/analytics/face_lbp/face_lbp_core.v rtl/analytics/face_lbp/face_candidate_select.v rtl/analytics/face_lbp/face_detector_snapshot.v rtl/analytics/face_lbp/face_pose_snapshot.v sim/face_pose/tb_face_pose.sv
 if($LASTEXITCODE){throw 'Pose compile failed'}
 $jobs=@()
 foreach($case in @('upright','close_2.9','roll_plus30','roll_minus30','fruits')){
  $log=Join-Path $outDir "${case}_modelsim.log"
  $console=Join-Path $outDir "${case}_console.log"
  $err=Join-Path $outDir "${case}_stderr.log"
  $arguments=@('-c','-lib',$work,'tb_face_pose',"+CASE=$case","-gREPORT_DIR=$reportDir",'-l',$log,'-do','"onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0"')
  $p=Start-Process -FilePath (Join-Path $ModelSimBin 'vsim.exe') -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $console -RedirectStandardError $err
  $jobs+=@{case=$case;process=$p;log=$log}
 }
 foreach($job in $jobs){
  $job.process.WaitForExit()
  $result=[IO.File]::ReadAllText($job.log)
  if($job.process.ExitCode -ne 0 -or $result -notmatch "PASS tb_face_pose $($job.case)" -or $result -match 'FAIL|\*\* (Error|Fatal)'){throw "Pose test failed: $($job.case)"}
  Write-Output "PASS $($job.case)"
 }
}finally{Pop-Location}
