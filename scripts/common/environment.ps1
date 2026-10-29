# Shared portable discovery; machine settings belong only in ignored .agent/local.ps1.
$script:RepositoryRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$local=Join-Path $script:RepositoryRoot '.agent/local.ps1'
if(Test-Path -LiteralPath $local){. $local}
if($env:TD_BIN -and $env:PATH.Split([IO.Path]::PathSeparator) -notcontains $env:TD_BIN){$env:PATH=$env:TD_BIN+[IO.Path]::PathSeparator+$env:PATH}
function Get-RepositoryRoot { $script:RepositoryRoot }
function Get-ProjectPython {
 if($env:PYTHON_EXE){return $env:PYTHON_EXE}
 $python=Get-Command python.exe -ErrorAction SilentlyContinue
 if(!$python){$python=Get-Command python3 -ErrorAction SilentlyContinue}
 if(!$python){throw 'Python unavailable. Add it to PATH or set PYTHON_EXE.'}
 return $python.Source
}
