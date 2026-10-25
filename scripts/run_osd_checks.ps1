param([string]$PlatformRoot='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PlatformRoot)
$sim=Join-Path $root 'sim'
$work=Join-Path $sim 'work_osd'
$vlog=(Get-Command vlog.exe -ErrorAction Stop).Source
$vsim=(Get-Command vsim.exe -ErrorAction Stop).Source
if(-not(Test-Path -LiteralPath $work)){& (Join-Path (Split-Path $vlog) 'vlib.exe') $work}
$osdSources=@(
 (Join-Path $root 'sim/osd_rom_sim_models.v'),
 (Join-Path $root 'user_source/hdl_source/hdmi_mixer.v'),
 (Join-Path $root 'sim/tb_ref_osd_mixer.v')
)
$modeSources=@(
 (Join-Path $root 'rtl/isp/pixel_cartoon.v'),
 (Join-Path $root 'rtl/isp/pixel_algorithm.v'),
 (Join-Path $root 'rtl/control/mode_ctrl.v'),
 (Join-Path $root 'sim/tb_pixel_algorithm_ref_modes.v'),
 (Join-Path $root 'sim/tb_mode_ctrl_ref_modes.v')
)
& $vlog -sv -work $work @osdSources *> (Join-Path $sim 'osd_port_compile.log')
if($LASTEXITCODE){throw 'OSD compile failed'}
& $vlog -sv -work $work @modeSources *> (Join-Path $sim 'osd_modes_compile.log')
if($LASTEXITCODE){throw 'mode/pixel compile failed'}
Push-Location $sim
try{
 foreach($test in @('tb_ref_osd_mixer','tb_pixel_algorithm_ref_modes','tb_mode_ctrl_ref_modes')){
  $log=Join-Path $sim ($test+'.log')
  & $vsim -c -lib $work $test -l $log -do 'run -all; quit -code 0' | Out-Null
  $text=[IO.File]::ReadAllText($log)
  if($LASTEXITCODE -or $text -notmatch "PASS $test" -or $text -match '\*\* Error|\*\* Fatal|FAIL'){throw "Check failed: $test; see $log"}
  Write-Output "PASS $test"
 }
}finally{Pop-Location}
