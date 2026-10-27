param([string]$RunName='yunet_probe_v45_r1',[switch]$Implement,[ValidateSet('dot','network','tracker')][string]$Unit='dot',[string]$NetworkSource='',[string]$DotSource='',[string]$TrackerSource='')
$ErrorActionPreference='Stop'
if($RunName -notmatch '^yunet_probe_[A-Za-z0-9_]+$'){throw 'Invalid isolated run name'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $root "td_project/$RunName"
if(Test-Path -LiteralPath $run){throw 'Preserve old probe; use a fresh run name'}
New-Item -ItemType Directory -Path $run|Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
function Resolve-ProbeSource([string]$Default,[string]$Override){
 $path=[IO.Path]::GetFullPath((Join-Path $root $(if($Override){$Override}else{$Default})))
 if(-not $path.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Probe source must be a workspace file'}
 return $path.Replace('\','/')
}
$rtl=if($Unit -eq 'tracker'){Resolve-ProbeSource 'rtl/analytics/vision_tasks/vision_sad_tracker.v' $TrackerSource}else{Resolve-ProbeSource 'rtl/analytics/face_cnn/yunet_dot4.v' $DotSource}
$hash=(Get-FileHash -LiteralPath $rtl -Algorithm SHA256).Hash
$files=@($rtl);$top='yunet_dot4'
if($Unit -eq 'network'){
 $cnn=(Join-Path $root 'rtl/analytics/face_cnn').Replace('\','/')
 $wrapper=@"
module yunet_network_probe(input wire clk,rst_n,start,load_valid,input wire [16:0] load_address,input wire [7:0] load_data,input wire [16:0] read_address,output wire [7:0] read_data,output wire busy,done,operation_done,output wire [5:0] operation_index,output wire [31:0] cycles);
yunet_network #(.PROGRAM_FILE("$cnn/program.hex"),.W0_FILE("$cnn/weights0.hex"),.W1_FILE("$cnn/weights1.hex"),.W2_FILE("$cnn/weights2.hex"),.W3_FILE("$cnn/weights3.hex"),.BIAS_FILE("$cnn/bias.hex"),.SHIFT_FILE("$cnn/shift.hex")) nn(.clk(clk),.rst_n(rst_n),.start(start),.load_valid(load_valid),.load_address(load_address),.load_data(load_data),.read_address(read_address),.read_data(read_data),.busy(busy),.done(done),.operation_done(operation_done),.operation_index(operation_index),.cycles(cycles));
endmodule
"@
 $wrapperPath=Join-Path $run 'network_probe.v'
 [IO.File]::WriteAllText($wrapperPath,$wrapper,$utf8)
 $networkFile=Resolve-ProbeSource 'rtl/analytics/face_cnn/yunet_network.v' $NetworkSource
 $files+=@($networkFile.Replace('\','/'),$wrapperPath.Replace('\','/'));$top='yunet_network_probe'
}
if($Unit -eq 'tracker'){
 $wrapper=@'
module vision_tracker_probe(input wire clk,rst_n,reseed,frame_start,sample_valid,frame_end,
 input wire [7:0] gray,shared_read_data,output wire result_valid,found,busy,
 output wire [7:0] center_x,center_y,quality,output wire [17:0] best_sad,second_sad,
 output wire [31:0] compute_cycles,output wire [1:0] lost_stage,
 output wire shared_write_en,output wire [13:0] shared_write_addr,shared_read_addr,output wire [7:0] shared_write_data);
 vision_sad_tracker #(.WIDTH(160),.HEIGHT(90),.RADIUS(8),.SCALE_ENABLE(1),.EXTERNAL_FRAME(1)) tracker(
 .clk(clk),.rst_n(rst_n),.reseed(reseed),.frame_start(frame_start),.sample_valid(sample_valid),.frame_end(frame_end),.gray(gray),
 .result_valid(result_valid),.found(found),.center_x(center_x),.center_y(center_y),.quality(quality),.best_sad(best_sad),.second_sad(second_sad),
 .busy(busy),.compute_cycles(compute_cycles),.lost_stage(lost_stage),.shared_write_en(shared_write_en),.shared_write_addr(shared_write_addr),
 .shared_read_addr(shared_read_addr),.shared_write_data(shared_write_data),.shared_read_data(shared_read_data));
endmodule
'@
 $wrapperPath=Join-Path $run 'tracker_probe.v';[IO.File]::WriteAllText($wrapperPath,$wrapper,$utf8)
 $files+=$wrapperPath.Replace('\','/');$top='vision_tracker_probe'
}
$sourceFiles=@($files)
if($Unit -eq 'network'){$sourceFiles+=Get-ChildItem -LiteralPath (Join-Path $root 'rtl/analytics/face_cnn') -Filter '*.hex'|ForEach-Object FullName}
$hashes=@($sourceFiles|ForEach-Object{[pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}})
[IO.File]::WriteAllText((Join-Path $run 'source_sha256.json'),($hashes|ConvertTo-Json),$utf8)
$fileEntries=($files|ForEach-Object{"<File Path=`"$_`"><FileInfo><Attr Name=`"UsedInSyn`" Val=`"true`"/><Attr Name=`"UsedInP&amp;R`" Val=`"true`"/></FileInfo></File>"}) -join "`n"
$project=@"
<?xml version="1.0"?><Project Version="3" Minor="2"><TD_Version>6.2.168116</TD_Version><Name>yunet_probe</Name><HardWare><Family>PH1</Family><Device>PH1P35MDG324</Device><Speed>-3</Speed></HardWare><Source_Files><Verilog>$fileEntries</Verilog></Source_Files></Project>
"@
[IO.File]::WriteAllText((Join-Path $run 'yunet_probe.prj'),$project,$utf8)
[IO.File]::WriteAllText((Join-Path $run 'probe.sdc'),'create_clock -name cnn_clk -period 13.333 [get_ports clk]',$utf8)
$td=(Get-Command td_commands_prompt.exe -ErrorAction Stop).Source
$flow=(Join-Path (Split-Path (Split-Path $td)) 'doc/scripts/DefaultFlow.tcl').Replace('\','/')
$last=if($Implement){'opt_route'}else{'opt_gate'}
$settings=@"
set ADCList {}
set IpADCList {}
set IpSDCList {}
set SDCList {probe.sdc}
set area_option -packarea
set device_name ph1_35p.db
set package_name PH1P35MDG324
set speed 3
set prj_name yunet_probe
set top_model_name $top
set run_type syn
set start_step read_design
set end_step $last
set synWildParams {rtl infer_fsm off}
set arr_filter false
set drHoldFix on
"@
[IO.File]::WriteAllText((Join-Path $run 'settings.cfg'),$settings,$utf8)
[IO.File]::WriteAllText((Join-Path $run 'run.tcl'),"if {[catch {source {$flow}} message]} {puts stderr `$message; exit 1}`nexit 0",$utf8)
$jobPath=Join-Path $root "reports/yunet_v45/${RunName}_job.json"
$scope=if($Unit -eq 'dot'){'Standalone shared convolution arithmetic only; not a complete detector or board image'}elseif($Unit -eq 'tracker'){'Standalone nine-bank SAD tracker with external frame; CNN, camera and display excluded'}else{'Standalone complete CNN feature/head engine; camera, position decoder and display integration excluded'}
$job=[ordered]@{status='running';scope=$scope;unit=$Unit;verification_stage=$last;implemented=[bool]$Implement;run=$RunName;pid=$PID;started_utc=[DateTime]::UtcNow.ToString('o');finished_utc=$null;source_sha256=$hashes;error=$null}
[IO.File]::WriteAllText($jobPath,($job|ConvertTo-Json),$utf8)
Push-Location $run
try{
 & $td run.tcl *> build_console.log
 if($LASTEXITCODE -or -not(Test-Path ".$last.end.f")){throw 'TD probe failed'}
 foreach($inputFile in $hashes){if((Get-FileHash -LiteralPath $inputFile.path -Algorithm SHA256).Hash -ne $inputFile.sha256){throw "Probe source changed during build: $($inputFile.path)"}}
 if($Implement){
  $timing=[IO.File]::ReadAllText((Join-Path $run 'yunet_probe_phy.ts'))
  $metrics=@{}
  foreach($name in @('SWNS','STNS','HWNS','HTNS')){
   $match=[regex]::Match($timing,($name+':\s*([-0-9.]+)ns'))
   if(-not $match.Success){throw "Missing routed metric: $name"}
   $metrics[$name]=[double]::Parse($match.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
  }
  $job['timing']=$metrics
  if($metrics.SWNS -lt 0 -or $metrics.HWNS -lt 0 -or $metrics.STNS -ne 0 -or $metrics.HTNS -ne 0){throw 'Routed timing failed; tool completion alone is not a passing probe'}
 }
 $job.status='passed'
}catch{$job.status='failed';$job.error=$_.Exception.Message}
finally{
 Pop-Location
 $job.finished_utc=[DateTime]::UtcNow.ToString('o')
 [IO.File]::WriteAllText($jobPath,($job|ConvertTo-Json),$utf8)
}
if($job.status -ne 'passed'){throw $job.error}
