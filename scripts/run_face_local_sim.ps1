param([string]$Variant='v40_local',[string[]]$Cases=@('upright','roll_plus30'),[int]$FullSequence=1,[int]$RequireAcceleration=1,[string]$ReportDir='v40_local')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$work=Join-Path $root "sim/face_pose/work_$Variant"
$out=Join-Path $root "reports/face_pose/$ReportDir"
New-Item -ItemType Directory -Force $out|Out-Null
Push-Location $root
try{
 if(-not(Test-Path $work)){& "$bin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
 & "$bin/vlog.exe" -sv -work $work rtl/analytics/face_lbp/face_lbp_core.v rtl/analytics/face_lbp/face_candidate_select.v rtl/analytics/face_lbp/face_detector_snapshot.v rtl/analytics/face_lbp/face_pose_snapshot.v sim/face_pose/tb_face_local_search.sv
 if($LASTEXITCODE){throw 'local compile failed'}
 $jobs=@()
 foreach($case in $Cases){
  $log=Join-Path $out "${case}_modelsim.log"
  $proc=Start-Process "$bin/vsim.exe" -ArgumentList @('-c','-lib',$work,'tb_face_local_search',"-gFULL_SEQUENCE=$FullSequence","-gREQUIRE_ACCELERATION=$RequireAcceleration","-gREPORT_DIR=reports/face_pose/$ReportDir","+CASE=$case",'-l',$log,'-do','"onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0"') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $out "${case}_console.log") -RedirectStandardError (Join-Path $out "${case}_stderr.log")
  $jobs+=@{proc=$proc;log=$log;case=$case}
 }
 foreach($job in $jobs){$job.proc.WaitForExit();$s=Get-Content $job.log -Raw;if($job.proc.ExitCode -or $s -notmatch "PASS tb_face_local_search $($job.case)" -or $s -match '\*\* (Error|Fatal)'){throw "local face failed $($job.case)"};Write-Output "PASS local $($job.case)"}
}finally{Pop-Location}
