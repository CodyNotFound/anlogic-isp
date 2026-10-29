param([switch]$SkipTracker)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));Push-Location $root
try{
 $python="$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
 & $python sim/face_cnn/check_head_offsets.py;if($LASTEXITCODE){throw 'head fixture failed'}
 $out=Join-Path $root 'build/dual_clock';New-Item -ItemType Directory -Force $out|Out-Null
 $bin='[LOCAL_PATH]';$work=Join-Path $out 'work'
 if(!(Test-Path $work)){& "$bin/vlib.exe" $work}
 $files=@('rtl/common/reset_sync.v','rtl/analytics/face_cnn/yunet_clock_bridge.v','rtl/analytics/face_cnn/yunet_dot4.v','rtl/analytics/face_cnn/yunet_network.v','rtl/analytics/face_cnn/yunet_decode.v','rtl/analytics/face_cnn/yunet_position_snapshot.v','rtl/analytics/face_cnn/yunet_rgb_snapshot.v','rtl/analytics/face_cnn/face_video_cnn.v','rtl/analytics/vision_tasks/vision_sad_tracker.v','rtl/analytics/vision_tasks/vision_motion_diff.v','rtl/analytics/vision_tasks/vision_unsigned_divider.v','rtl/analytics/vision_tasks/vision_color_region.v')
 $tests=@('tb_yunet_clock_bridge','tb_yunet_dual_arena','tb_yunet_dual_heads','tb_yunet_dual_motion','tb_yunet_dual_color');if(!$SkipTracker){$tests+='tb_yunet_dual_tracker'}
 $tbFiles=@($tests|ForEach-Object {"sim/face_cnn/$_.sv"})
 & "$bin/vlog.exe" -sv +incdir+rtl/analytics/face_cnn -work $work @files @tbFiles *> (Join-Path $out 'compile.log')
 $log=[IO.File]::ReadAllText((Join-Path $out 'compile.log'));if($LASTEXITCODE -or $log -notmatch 'Errors: 0, Warnings: 0'){throw 'dual-clock compile failed'}
 foreach($test in $tests){
  & "$bin/vsim.exe" -c -lib $work $test -l (Join-Path $out "$test.log") -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0'
  $log=[IO.File]::ReadAllText((Join-Path $out "$test.log"));if($LASTEXITCODE -or $log -notmatch "PASS $test" -or $log -notmatch 'Errors: 0, Warnings: 0'){throw "dual-clock regression failed: $test"}
 }
 $snapshot=foreach($name in $files){[ordered]@{path=$name;sha256=(Get-FileHash $name -Algorithm SHA256).Hash}}
 [ordered]@{status='passed';tests=$tests;source_sha256=$snapshot}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $out 'completion.json') -Encoding UTF8
}finally{Pop-Location}