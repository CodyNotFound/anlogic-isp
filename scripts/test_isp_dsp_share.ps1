$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Push-Location $root
try{
 $out=Join-Path $root 'build/isp_dsp_share';New-Item -ItemType Directory -Force $out|Out-Null
 $bin='[LOCAL_PATH]';$work=Join-Path $out 'work'
 if(!(Test-Path $work)){& "$bin/vlib.exe" $work}
 & "$bin/vlog.exe" -sv +incdir+rtl/isp -work $work rtl/isp/frame_awb4.v rtl/isp/raw_lsc_grid4.v sim/reference/frame_awb4_throughput_ref.v sim/reference/raw_lsc_grid4_throughput_ref.v sim/tb_isp_dsp_share.sv *> (Join-Path $out 'compile.log')
 if($LASTEXITCODE){throw 'ISP regression compile failed'}
 foreach($test in @('tb_awb_dsp_share','tb_lsc_dsp_share')){
  & "$bin/vsim.exe" -c -lib $work $test -l (Join-Path $out "$test.log") -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $log=Get-Content (Join-Path $out "$test.log") -Raw
  if($LASTEXITCODE -or $log -notmatch "PASS $test" -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "ISP regression failed: $test"}
 }
 $snapshot=foreach($name in @('rtl/isp/frame_awb4.v','rtl/isp/raw_lsc_grid4.v','rtl/isp/colorshading_lut_case.vh','sim/reference/frame_awb4_throughput_ref.v','sim/reference/raw_lsc_grid4_throughput_ref.v','sim/tb_isp_dsp_share.sv')){[ordered]@{path=$name;sha256=(Get-FileHash $name -Algorithm SHA256).Hash}}
 [ordered]@{status='passed';tests=@('tb_awb_dsp_share','tb_lsc_dsp_share');source_sha256=$snapshot}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $out 'completion.json') -Encoding UTF8
}finally{Pop-Location}