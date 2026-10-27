param([string[]]$Cases=@('lena','close_roll_-30','fruits'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ms='[LOCAL_PATH]'
$work=Join-Path $root 'reports/yunet_v45/work_position'
Push-Location $root
try{
 if(-not(Test-Path -LiteralPath $work)){& "$ms/vlib.exe" $work}
 & "$ms/vlog.exe" -sv '+incdir+rtl/analytics/face_cnn' -work $work rtl/analytics/face_cnn/yunet_dot4.v rtl/analytics/face_cnn/yunet_network.v rtl/analytics/face_cnn/yunet_decode.v rtl/analytics/face_cnn/yunet_position_snapshot.v sim/face_cnn/tb_yunet_position.sv *> reports/yunet_v45/position_compile.log
 if($LASTEXITCODE){throw 'Position compile failed'}
 $jobs=@()
 foreach($case in $Cases){
  if($case -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid case'}
  $log=Join-Path $root "reports/yunet_v45/position_${case}.log"
  $proc=Start-Process "$ms/vsim.exe" -ArgumentList @('-c','-lib',$work,'tb_yunet_position',"+CASE=$case",'-l',$log,'-do','"onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0"') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $root "reports/yunet_v45/position_${case}_console.log") -RedirectStandardError (Join-Path $root "reports/yunet_v45/position_${case}_stderr.log")
  $jobs+=@{proc=$proc;log=$log;case=$case}
 }
 foreach($job in $jobs){
  $job.proc.WaitForExit();$s=[IO.File]::ReadAllText($job.log)
  if($job.proc.ExitCode -or $s -notmatch "PASS tb_yunet_position $($job.case)" -or $s -match '\*\* (Error|Fatal)'){throw "Position failed: $($job.case)"}
  Write-Output "PASS full integer position $($job.case)"
 }
}finally{Pop-Location}
