param([string]$RunName='face_lbp_probe_r1',[switch]$Implement)
$ErrorActionPreference='Stop'
if($RunName -notmatch '^face_lbp_probe_[A-Za-z0-9_]+$'){throw 'Invalid run name'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $root "td_project/$RunName"
if(Test-Path $run){throw 'Use a new run name to preserve evidence'}
New-Item -ItemType Directory -Path $run | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$rtl=(Join-Path $root 'rtl/analytics/face_lbp').Replace('\','/')
$ports=@'
input wire clk,rst_n,frame_start,pixel_valid,model_select,
input wire [7:0] gray,
output wire ready,busy,result_valid,target_found,overflow,
output wire [7:0] target_x,target_y,target_size,target_votes,
output wire [8:0] target_center_x,target_center_y,
output wire [31:0] cycles,feature_count
'@
$connections=(@('clk','rst_n','frame_start','pixel_valid','model_select','gray','ready','busy','result_valid','target_found','overflow','target_x','target_y','target_size','target_votes','target_center_x','target_center_y','cycles','feature_count') | ForEach-Object {'.'+$_+'('+$_+')'}) -join ','
$wrapper="module face_lbp_probe_top($ports);`nface_detector_snapshot #(.WEAK_FILE(`"$rtl/weak.hex`"),.STAGE_FILE(`"$rtl/stage.hex`"),.GEOMETRY_FILE(`"$rtl/geometry.hex`")) detector($connections);`nendmodule`n"
[IO.File]::WriteAllText((Join-Path $run 'probe_top.sv'),$wrapper,$utf8)
$files=@("$rtl/face_lbp_core.v","$rtl/face_candidate_select.v","$rtl/face_detector_snapshot.v",((Join-Path $run 'probe_top.sv').Replace('\','/')))
$sources=($files | ForEach-Object {"<File Path=`"$_`"><FileInfo><Attr Name=`"UsedInSyn`" Val=`"true`"/><Attr Name=`"UsedInP&amp;R`" Val=`"true`"/></FileInfo></File>"}) -join "`n"
$project="<?xml version=`"1.0`"?><Project Version=`"3`" Minor=`"2`"><TD_Version>6.2.168116</TD_Version><Name>face_lbp_probe</Name><HardWare><Family>PH1</Family><Device>PH1P35MDG324</Device><Speed>-3</Speed></HardWare><Source_Files><Verilog>$sources</Verilog></Source_Files></Project>"
[IO.File]::WriteAllText((Join-Path $run 'face_lbp_probe.prj'),$project,$utf8)
[IO.File]::WriteAllText((Join-Path $run 'face.sdc'),'create_clock -name detector_clk -period 13.468 [get_ports clk]',$utf8)
$td=(Get-Command td_commands_prompt.exe -ErrorAction Stop).Source
$flow=(Join-Path (Split-Path (Split-Path $td)) 'doc/scripts/DefaultFlow.tcl').Replace('\','/')
$last=if($Implement){'opt_route'}else{'opt_gate'}
$settings=@"
set ADCList {}
set IpADCList {}
set IpSDCList {}
set SDCList {face.sdc}
set area_option -packarea
set device_name ph1_35p.db
set package_name PH1P35MDG324
set speed 3
set prj_name face_lbp_probe
set top_model_name face_lbp_probe_top
set run_type syn
set start_step read_design
set end_step $last
set synWildParams {rtl infer_fsm off}
set arr_filter false
set drHoldFix on
"@
[IO.File]::WriteAllText((Join-Path $run 'settings.cfg'),$settings,$utf8)
[IO.File]::WriteAllText((Join-Path $run 'run.tcl'),"if {[catch {source {$flow}} message]} {puts stderr `$message; exit 1}`nexit 0",$utf8)
$manifest=Get-ChildItem $rtl -File | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash
$manifest | ConvertTo-Json | Set-Content (Join-Path $run 'source_sha256.json')
Push-Location $run
try {
 & $td run.tcl 2>&1 | Tee-Object -FilePath build_console.log
 if($LASTEXITCODE -ne 0 -or -not (Test-Path ".$last.end.f")){throw 'Standalone detector TD probe failed'}
} finally {Pop-Location}
