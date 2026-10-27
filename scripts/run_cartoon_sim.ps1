param([switch]$SkipPrepare)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$python='[LOCAL_PATH]'
$bin='[LOCAL_PATH]'
$work=Join-Path $root 'sim/cartoon/work_v41'
Push-Location $root
try{
 if(-not $SkipPrepare){& $python scripts/cartoon_v41_reference.py;if($LASTEXITCODE){throw 'Reference failed'}}
 if(-not(Test-Path $work)){& "$bin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
 & "$bin/vlog.exe" -sv -work $work rtl/isp/pixel_cartoon.v sim/cartoon/tb_pixel_cartoon.sv
 if($LASTEXITCODE){throw 'Cartoon compile failed'}
 $jobs=@()
 foreach($name in @('lena','fruits','grace_hopper','figurine','probes')){
  $log="reports/cartoon_v41/${name}_modelsim.log"
  $args=@('-c','-lib',$work,'tb_pixel_cartoon',"+CASE=$name",'-l',$log)
  if($name -eq 'probes'){$args+=@('-gWIDTH=24','-gHEIGHT=12','-gSEQUENCE=1')}
  $args+=@('-do','"onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0"')
  $proc=Start-Process "$bin/vsim.exe" -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput "reports/cartoon_v41/${name}_console.log" -RedirectStandardError "reports/cartoon_v41/${name}_stderr.log"
  $jobs+=@{proc=$proc;name=$name;log=$log}
 }
 foreach($job in $jobs){$job.proc.WaitForExit();$s=Get-Content $job.log -Raw;if($job.proc.ExitCode -or $s -notmatch 'PASS tb_pixel_cartoon' -or $s -match '\*\* (Error|Fatal)|\bFAIL\b'){throw "Cartoon failed: $($job.name)"};Write-Output "PASS cartoon $($job.name)"}
}finally{Pop-Location}
