param([string]$PlatformRoot='[LOCAL_PATH]')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PlatformRoot)
$sim=Join-Path $root 'sim'
$vlog=(Get-Command vlog.exe -ErrorAction Stop).Source
$vsim=(Get-Command vsim.exe -ErrorAction Stop).Source
$libLogo=Join-Path $sim 'work_v12_logo'
$libMc=Join-Path $sim 'work_v12_mc'
if(-not(Test-Path -LiteralPath $libLogo)){& (Join-Path (Split-Path $vlog) 'vlib.exe') $libLogo}
if(-not(Test-Path -LiteralPath $libMc)){& (Join-Path (Split-Path $vlog) 'vlib.exe') $libMc}
$logoSources=@((Join-Path $sim 'osd_rom_real_models.v'),(Join-Path $root 'user_source/hdl_source/hdmi_mixer.v'),(Join-Path $sim 'tb_osd_logo_shape.v'))
$mcSources=@((Join-Path $sim 'mc_to_user_interface_v9_reference.v'),(Join-Path $root 'user_source/hdl_source/mc_to_user_interface.v'),(Join-Path $root 'user_source/ip_source/w155_d512_fifo/w155_d512_fifo.v'),(Join-Path $root 'user_source/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v'),(Join-Path $sim 'tb_mc_command_handshake.v'))
& $vlog -sv -work $libLogo @logoSources *> (Join-Path $sim 'v12_logo_compile.log')
if($LASTEXITCODE){throw 'logo compile failed'}
& $vlog -sv -work $libMc @mcSources *> (Join-Path $sim 'v12_mc_compile.log')
if($LASTEXITCODE){throw 'MC compile failed'}
Push-Location $sim
try{
    foreach($test in @(@('tb_osd_logo_shape',$libLogo),@('tb_mc_command_handshake',$libMc))){
        $log=Join-Path $sim ($test[0]+'.log')
        & $vsim -c -lib $test[1] $test[0] -l $log -do 'run -all; quit -code 0' | Out-Null
        $text=[IO.File]::ReadAllText($log)
        if($LASTEXITCODE -or $text -notmatch "PASS $($test[0])" -or $text -match '\*\* Error|\*\* Fatal|FAIL'){throw "Failed: $($test[0]); see $log"}
        Write-Output "PASS $($test[0])"
    }
}
finally{Pop-Location}
& (Join-Path $root 'scripts/run_osd_checks.ps1') -PlatformRoot $root
