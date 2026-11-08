param([string]$ModelSimExe='D:/modelsim/win64/vsim.exe')
$simPath=$PSScriptRoot.Replace('\','/')
Push-Location $PSScriptRoot
try {
 & $ModelSimExe -c -l "$PSScriptRoot/modelsim_fusion.log" -do "set r {$simPath}; do {$simPath/run_fusion.do}"
 $simExit=$LASTEXITCODE
} finally { Pop-Location }
exit $simExit
