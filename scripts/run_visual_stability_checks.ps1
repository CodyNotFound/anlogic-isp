param()
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $root
try {
    & vlib.exe sim/work_visual_stability | Out-Null
    if($LASTEXITCODE){throw 'vlib failed'}
    & vlog.exe -sv -work sim/work_visual_stability rtl/isp/color_tone4.v rtl/isp/frame_awb4.v sim/tb_color_tone4.v sim/tb_awb_deadband.v sim/tb_awb_bypass.v *> sim/visual_stability_compile.log
    if($LASTEXITCODE){throw 'visual stability compile failed'}
    Push-Location sim
    try {
        foreach($test in @('tb_color_tone4','tb_awb_deadband','tb_awb_bypass')){
            & vsim.exe -c -lib work_visual_stability $test -l "$test`_visual.log" -do 'run -all; quit -code 0' *> "$test`_visual_console.log"
            $text=Get-Content -LiteralPath "$test`_visual.log" -Raw
            if($LASTEXITCODE -or $text -notmatch "PASS $test" -or $text -match '\*\* Error|\*\* Fatal|FAIL'){throw "Failed $test"}
            Write-Output "PASS $test"
        }
    } finally { Pop-Location }
    & scripts/run_flicker_checks.ps1 *> sim/visual_stability_flicker.log
    & scripts/run_osd_checks.ps1 *> sim/visual_stability_osd.log
    Write-Output 'PASS visual stability focused regressions'
} finally { Pop-Location }

