param(
 [string]$ModelSimBin='[LOCAL_PATH]',
 [string]$Python='[LOCAL_PATH]',
 [string]$ModelDirectory=''
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path $root 'sim/object_classifier/work'
Push-Location $root
try {
 if($ModelDirectory){$models=@($ModelDirectory)}else{
  & $Python scripts/object_classifier_model.py --selftest
  if($LASTEXITCODE -ne 0){throw 'Selftest model generation failed'}
  $models=@('sim/object_classifier/selftest/arithmetic','sim/object_classifier/selftest/ties','sim/object_classifier/selftest/negative','sim/object_classifier/selftest/wide_margin','sim/object_classifier/selftest/full_range')
 }
 if(-not (Test-Path $work)){
  & (Join-Path $ModelSimBin 'vlib.exe') $work
  if($LASTEXITCODE -ne 0){throw 'vlib failed'}
 }
 & (Join-Path $ModelSimBin 'vlog.exe') -sv -work $work rtl/analytics/object_classifier/object_classifier_q8.v sim/object_classifier/tb_object_classifier.sv
 if($LASTEXITCODE -ne 0){throw 'vlog failed'}
 $index=0
 foreach($model in $models){
  $tag=if($ModelDirectory){'external_vectors'}else{Split-Path $model -Leaf}
  $log="reports/object_classifier/${tag}_modelsim.log"
  $csv="reports/object_classifier/${tag}_rtl.csv"
  $modelFull=[IO.Path]::GetFullPath((Join-Path $root $model)).Replace('\','/')
  if(-not (Test-Path (Join-Path $modelFull 'export_manifest.json'))){throw 'Run model exporter first'}
  & (Join-Path $ModelSimBin 'vsim.exe') -c -lib $work tb_object_classifier "-gMODEL_DIR=$modelFull" "+RESULTS_PATH=$csv" -do 'onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -code 0' -l $log
  $result=[IO.File]::ReadAllText((Join-Path $root $log))
  if($LASTEXITCODE -ne 0 -or $result -notmatch 'PASS ALL OBJECT' -or $result -match 'FAIL|\*\* Error|\*\* Fatal'){throw "Integer RTL simulation failed: $tag"}
  $index++
 }
}finally{Pop-Location}
