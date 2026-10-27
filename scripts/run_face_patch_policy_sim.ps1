$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bin='[LOCAL_PATH]'
$work=Join-Path $root 'reports/tracking_v40/patch_policy_work'
Push-Location $root
try{
 New-Item -ItemType Directory -Force reports/tracking_v40|Out-Null
 if(-not(Test-Path $work)){& "$bin/vlib.exe" $work;if($LASTEXITCODE){throw 'vlib failed'}}
 # Deliberately omit the real cascade: this test isolates bounded hold policy.
 & "$bin/vlog.exe" -sv -work $work rtl/analytics/face_lbp/face_pose_snapshot.v sim/face_pose/tb_face_patch_policy.sv *> reports/tracking_v40/patch_policy_compile.log
 if($LASTEXITCODE){throw 'patch policy compile failed'}
 & "$bin/vsim.exe" -c -lib $work tb_face_patch_policy -l reports/tracking_v40/patch_policy.log -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' *> reports/tracking_v40/patch_policy_console.log
 $s=Get-Content reports/tracking_v40/patch_policy.log -Raw
 if($LASTEXITCODE -or $s -notmatch 'PASS tb_face_patch_policy' -or $s -match '\*\* (Error|Fatal)'){throw 'patch policy failed'}
 Write-Output 'PASS patch policy (cascade stub; not accuracy evidence)'
}finally{Pop-Location}
