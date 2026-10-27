param([string]$RunName='object_classifier_probe_r1',[switch]$Implement)
$ErrorActionPreference='Stop'
if($RunName -notmatch '^object_classifier_probe_[A-Za-z0-9_]+$'){throw 'Invalid run name'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $root "td_project/$RunName"
if(Test-Path $run){throw 'Use a new run name to preserve evidence'}
New-Item -ItemType Directory -Path $run | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$rtl=(Join-Path $root 'rtl/analytics/object_classifier').Replace('\','/')
$model=(Join-Path $root 'sim/object_classifier/selftest/full_range').Replace('\','/')
if(-not (Test-Path "$model/weights.hex")){throw 'Run object_classifier_model.py --selftest first'}
$ports=@'
input wire clk,rst_n,frame_start,pixel_valid,
input wire [23:0] pixel_rgb,
output wire ready,busy,result_valid,rejected,
output wire [1:0] class_id,
output wire signed [31:0] best_score,
output wire [31:0] score_margin,cycles
'@
$connections=(@('clk','rst_n','frame_start','pixel_valid','pixel_rgb','ready','busy','result_valid','rejected','class_id','best_score','score_margin','cycles') | ForEach-Object {'.'+$_+'('+$_+')'}) -join ','
$wrapper="module object_classifier_probe_top($ports);`nobject_classifier_q8 #(.WEIGHT_FILE(`"$model/weights.hex`"),.BIAS_FILE(`"$model/bias.hex`"),.SHIFT_FILE(`"$model/shift.hex`"),.REJECT_FILE(`"$model/reject.hex`")) classifier($connections,.mac_count(),.logit0(),.logit1(),.logit2(),.logit3());`nendmodule`n"
[IO.File]::WriteAllText((Join-Path $run 'probe_top.v'),$wrapper,$utf8)
$files=@("$rtl/object_classifier_q8.v",((Join-Path $run 'probe_top.v').Replace('\','/')))
$sources=($files | ForEach-Object {"<File Path=`"$_`"><FileInfo><Attr Name=`"UsedInSyn`" Val=`"true`"/><Attr Name=`"UsedInP&amp;R`" Val=`"true`"/></FileInfo></File>"}) -join "`n"
$project="<?xml version=`"1.0`"?><Project Version=`"3`" Minor=`"2`"><TD_Version>6.2.168116</TD_Version><Name>object_classifier_probe</Name><HardWare><Family>PH1</Family><Device>PH1P35MDG324</Device><Speed>-3</Speed></HardWare><Source_Files><Verilog>$sources</Verilog></Source_Files></Project>"
[IO.File]::WriteAllText((Join-Path $run 'object_classifier_probe.prj'),$project,$utf8)
[IO.File]::WriteAllText((Join-Path $run 'classifier.sdc'),'create_clock -name classifier_clk -period 13.468 [get_ports clk]',$utf8)
$td=(Get-Command td_commands_prompt.exe -ErrorAction Stop).Source
$flow=(Join-Path (Split-Path (Split-Path $td)) 'doc/scripts/DefaultFlow.tcl').Replace('\','/')
$last=if($Implement){'opt_route'}else{'opt_gate'}
$settings=@"
set ADCList {}
set IpADCList {}
set IpSDCList {}
set SDCList {classifier.sdc}
set area_option -packarea
set device_name ph1_35p.db
set package_name PH1P35MDG324
set speed 3
set prj_name object_classifier_probe
set top_model_name object_classifier_probe_top
set run_type syn
set start_step read_design
set end_step $last
set synWildParams {rtl infer_fsm off}
set arr_filter false
set drHoldFix on
"@
[IO.File]::WriteAllText((Join-Path $run 'settings.cfg'),$settings,$utf8)
[IO.File]::WriteAllText((Join-Path $run 'run.tcl'),"if {[catch {source {$flow}} message]} {puts stderr `$message; exit 1}`nexit 0",$utf8)
$manifest=@("$rtl/object_classifier_q8.v","$model/weights.hex","$model/bias.hex","$model/shift.hex","$model/reject.hex") | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash
$manifest | ConvertTo-Json | Set-Content (Join-Path $run 'source_sha256.json')
Push-Location $run
try {
 & $td run.tcl *> build_console.log
 if($LASTEXITCODE -ne 0 -or -not (Test-Path ".$last.end.f")){throw "Standalone classifier TD probe failed: $run/build_console.log"}
}finally{Pop-Location}
