param([string]$ModelSimBin = 'D:/modelsim/win64')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logRoot = Join-Path $PSScriptRoot 'algo7_color'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('algo7_color_ascii_' + [Guid]::NewGuid().ToString('N'))
if ($tempRoot -match '[^\x00-\x7F]') { throw "ModelSim temp path must be ASCII: $tempRoot" }
New-Item -ItemType Directory -Force -Path $tempRoot,$logRoot | Out-Null
$sources = @(
    '../user_source/algorithms/algo_polar_core.v',
    '../user_source/algorithms/algo_fusion.v',
    '../user_source/algorithms/algo_polar_fusion.v',
    '../user_source/algorithms/line_buffer_3x3_sparse.v',
    '../user_source/algorithms/algo_edge_polar.v',
    '../user_source/algorithms/polar_block_engine.v',
    'sim/tb_algo7_color.v'
)
foreach ($source in $sources) { Copy-Item -LiteralPath (Join-Path $repo $source) -Destination $tempRoot }
Copy-Item -LiteralPath (Join-Path $repo '../user_source/ddr_page_map.vh') -Destination $tempRoot
New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'include_anchor') | Out-Null
    Push-Location $tempRoot
try {
    $lib = & (Join-Path $ModelSimBin 'vlib.exe') work 2>&1
    if ($LASTEXITCODE -ne 0) { throw "vlib failed: $($lib -join ' ')" }
    $files = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.v' | ForEach-Object FullName)
    $compile = & (Join-Path $ModelSimBin 'vlog.exe') '+incdir+include_anchor' -work work @files 2>&1
    $compileCode = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $tempRoot 'compile.log'), [string[]]$compile, [Text.Encoding]::ASCII)
    Copy-Item -LiteralPath (Join-Path $tempRoot 'compile.log') -Destination (Join-Path $logRoot 'color.compile.log') -Force
    $compileText = $compile -join "`n"
    if ($compileCode -ne 0 -or $compileText -match '\*\* (Error|Fatal)') { throw "vlog failed; see $tempRoot/compile.log" }
    $run = & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -lib work tb_algo7_color -do 'run -all; quit -f' 2>&1
    $runCode = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $tempRoot 'simulation.log'), [string[]]$run, [Text.Encoding]::ASCII)
    Copy-Item -LiteralPath (Join-Path $tempRoot 'simulation.log') -Destination (Join-Path $logRoot 'color.simulation.log') -Force
    $runText = $run -join "`n"
    if ($runCode -ne 0 -or $runText -match '\*\* (Error|Fatal)|FAIL' -or $runText -notmatch 'PASS tb_algo7_color') {
        throw "vsim failed (exit=$runCode); see $tempRoot/simulation.log"
    }
    $run | Where-Object { $_ -match 'PASS tb_algo7_color' }
    Write-Output "ModelSim logs: $tempRoot"
} catch {
    Write-Output "ASCII ModelSim workspace retained at: $tempRoot"
    throw
} finally { Pop-Location }
