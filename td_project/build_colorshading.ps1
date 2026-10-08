param(
    [ValidateSet('Check','Synthesis','Implementation')]
    [string]$Stage = 'Check',
    [string]$RunName = 'colorshading_runs_20261014_v5',
    [switch]$AllowGateTimingExploration,
  [switch]$DisableFsmInference,
  [int]$MinControlSet = -1,
  [int]$MinRippleLength = -1
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($RunName -notmatch '^colorshading_runs_[A-Za-z0-9_]+$') { throw 'Invalid isolated run name.' }
$runRoot = Join-Path $PSScriptRoot $RunName
$synDir = Join-Path $runRoot 'syn'
$phyDir = Join-Path $runRoot 'phy'
$tdTool = (Get-Command td_commands_prompt.exe -ErrorAction SilentlyContinue).Source
if (-not $tdTool) {
    $tdGui = (Get-Command td.exe -ErrorAction Stop).Source
    $tdTool = Join-Path (Split-Path $tdGui) 'td_commands_prompt.exe'
}
$tdFlow = Join-Path (Split-Path (Split-Path $tdTool)) 'doc/scripts/DefaultFlow.tcl'
if (-not (Test-Path -LiteralPath $tdFlow)) { throw "TD flow missing: $tdFlow" }
$name = 'camera_to_dsi_display'
$alFile = Join-Path $PSScriptRoot ($name+'.al')
$utf8 = [Text.UTF8Encoding]::new($false)
$alText = [IO.File]::ReadAllText($alFile)
$sources = foreach ($match in [regex]::Matches($alText,'<File Path="([^"]+)"')) {
    $resolved = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $match.Groups[1].Value))
    if (-not (Test-Path -LiteralPath $resolved)) { throw "Project source missing: $resolved" }
    $resolved
}
$sources += Get-ChildItem -LiteralPath (Join-Path $projectRoot 'rtl/isp') -Filter 'colorshading_*.vh' | ForEach-Object { $_.FullName }
New-Item -ItemType Directory -Force -Path $synDir,$phyDir | Out-Null
$manifest = foreach ($source in ($sources | Sort-Object -Unique)) {
    $hash = Get-FileHash -LiteralPath $source -Algorithm SHA256
    '{0}  {1}' -f $hash.Hash, $(if ($source.StartsWith($projectRoot)) { $source.Substring($projectRoot.Length+1) } else { $source })
}
$hashText = $manifest -join [Environment]::NewLine
$snapshot = Join-Path $runRoot 'source_sha256.txt'
if ($Stage -eq 'Check') {
    if (Test-Path -LiteralPath (Join-Path $synDir ($name+'_elaborate.db'))) {
        throw 'Check already ran in this isolated directory; preserve evidence before choosing a fresh run name.'
    }
    [IO.File]::WriteAllText($snapshot,$hashText,$utf8)
} else {
    if (-not (Test-Path -LiteralPath $snapshot)) { throw 'Run Check first.' }
    if ([IO.File]::ReadAllText($snapshot) -ne $hashText) { throw 'Sources changed after Check; refuse stale-netlist build.' }
}
foreach ($dir in @($synDir,$phyDir)) {
    # PS5.1无[IO.Path]::GetRelativePath, 手写逐段对比(大小写不敏感)生成 ../ 相对路径并固定用/
    $localProject = [regex]::Replace($alText,'<File Path="([^"]+)"', {
        param($match)
        $absolute = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $match.Groups[1].Value))
        $fromParts = $dir -split '[\\/]'
        $toParts   = $absolute -split '[\\/]'
        $i = 0
        while ($i -lt $fromParts.Count -and $i -lt $toParts.Count -and $fromParts[$i] -ieq $toParts[$i]) { $i++ }
        $ups = $fromParts.Count - $i
        $rel = ((@('..') * $ups) + $toParts[$i..($toParts.Count-1)]) -join '/'
        '<File Path="'+$rel+'"'
    })
    [IO.File]::WriteAllText((Join-Path $dir ($name+'.prj')),$localProject,$utf8)
}
$settings = @'
set ADCList {"../../../user_source/constraints_source/pin.adc"}
set IpADCList { ddr2 ../../../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc }
set IpSDCList { ddr2 ../../../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc w128_d512_fifo ../../../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl }
set SDCList {"../../camera_to_dsi_display.sdc"}
set area_option -packarea
set device_name ph1_35p.db
set package_name PH1P35MDG324
set speed 3
set prj_name {camera_to_dsi_display}
set top_model_name {design_top_wrapper}
'@
$synWildParams=@()
if ($DisableFsmInference) { $synWildParams += @('rtl','infer_fsm','off') }
if ($MinControlSet -ge 0) { $synWildParams += @('rtl','min_control_set',[string]$MinControlSet) }
if ($MinRippleLength -ge 0) { $synWildParams += @('rtl','min_ripple_len',[string]$MinRippleLength) }
if ($synWildParams.Count) { $settings += "`nset synWildParams {$($synWildParams -join ' ')}`n" }
switch ($Stage) {
    'Check' { $dir=$synDir; $start='read_design'; $end='read_design'; $kind='syn'; $extra='' }
    'Synthesis' {
        if (-not (Test-Path -LiteralPath (Join-Path $synDir '.read_design.end.f'))) { throw 'Check did not pass.' }
        $dir=$synDir; $start='opt_rtl'; $end='opt_gate'; $kind='syn'; $extra=''
    }
    'Implementation' {
        if (-not (Test-Path -LiteralPath (Join-Path $synDir '.opt_gate.end.f'))) { throw 'Synthesis did not pass.' }
        $gateTiming = [IO.File]::ReadAllText((Join-Path $synDir ($name+'_gate.ts')))
        $gateSlack = [regex]::Match($gateTiming,'SWNS:\s*([-0-9.]+)ns')
        if (-not $gateSlack.Success) { throw 'Cannot read gate timing; review before implementation.' }
        if ([double]::Parse($gateSlack.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0 -and -not $AllowGateTimingExploration) {
            throw 'Gate setup timing is negative; use AllowGateTimingExploration only when a reviewed routed comparison justifies a placement probe.'
        }
        $dir=$phyDir; $start='opt_place'; $end='bitgen'; $kind='phy'
        $extra="set parent ../syn`nset arr_filter false`nset drHoldFix on"
    }
}
$settings += "`nset run_type $kind`nset start_step $start`nset end_step $end`n$extra`n"
[IO.File]::WriteAllText((Join-Path $dir 'settings.cfg'),$settings,$utf8)
$flowPath = $tdFlow.Replace('\','/')
$wrapper = @'
if {[catch {source {@FLOW@}} message]} {
    puts stderr $message
    exit 1
}
exit 0
'@
$wrapper = $wrapper.Replace('@FLOW@',$flowPath)
[IO.File]::WriteAllText((Join-Path $dir 'run_checked.tcl'),$wrapper,$utf8)
Push-Location $dir
try {
    & $tdTool 'run_checked.tcl' 2>&1 | Tee-Object -FilePath ($Stage.ToLower()+'.log') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "TD $Stage failed with exit $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath ('.'+$end+'.end.f'))) { throw "TD $end success marker missing." }
} finally { Pop-Location }

