param([string]$ModelSimBin = 'D:\modelsim\win64')
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('shared_ddr_720p_' + [Guid]::NewGuid().ToString('N'))
$logRoot = Join-Path $PSScriptRoot 'shared_ddr_720p'
New-Item -ItemType Directory -Force -Path $testRoot, $logRoot | Out-Null

$sources = @(
    'sim/tb_shared_ddr_720p.v',
    '../user_source/hdl_source/video_in.v',
    '../user_source/hdl_source/video_out.v',
    '../user_source/hdl_source/hdmi_mixer.v',
    '../user_source/hdl_source/vtc/uivtc.v',
    '../user_source/algorithms/polar_ddr_arbiter.v',
    '../user_source/algorithms/reset_sync.v',
    '../user_source/algorithms/frame_mailbox_cdc.v',
    '../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.v',
    '../user_source/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v'
)
foreach ($source in $sources) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $source) -Destination $testRoot
}
# ModelSim's SQLite libraries fail in the original Chinese-path project; keep all inputs in ASCII temp.
Copy-Item -LiteralPath (Join-Path $projectRoot '../user_source/ddr_page_map.vh') -Destination $testRoot
$inputHashes = @($sources + @('../user_source/ddr_page_map.vh') | ForEach-Object {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $projectRoot $_) -Algorithm SHA256).Hash
    $copiedHash = (Get-FileHash -LiteralPath (Join-Path $testRoot ([IO.Path]::GetFileName($_))) -Algorithm SHA256).Hash
    if ($sourceHash -ne $copiedHash) { throw "Staged input differs: $_" }
    [pscustomobject]@{Path=$_;SourceSHA256=$sourceHash;StagedSHA256=$copiedHash}
})
$inputHashes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logRoot 'inputs.json') -Encoding utf8
New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'include_anchor') | Out-Null
    Push-Location $testRoot
try {
    & "$ModelSimBin\vlib.exe" work 2>&1 | Out-File -Encoding ascii (Join-Path $logRoot 'vlib.log')
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit code $LASTEXITCODE" }

    $compileArgs = @('-work', 'work', '+incdir+.') + (Get-ChildItem -LiteralPath $testRoot -Filter '*.v' | ForEach-Object FullName)
    & "$ModelSimBin\vlog.exe" '+incdir+include_anchor' @compileArgs 2>&1 | Out-File -Encoding ascii (Join-Path $logRoot 'compile.log')
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit code $LASTEXITCODE" }

    $ErrorActionPreference = 'Continue'
    & "$ModelSimBin\vsim.exe" -c -onfinish exit -lib work tb_shared_ddr_720p -do 'run -all; quit -f' 2>&1 | Out-File -Encoding ascii (Join-Path $logRoot 'simulation.log')
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit code $LASTEXITCODE" }
    $simulationText = [IO.File]::ReadAllText((Join-Path $logRoot 'simulation.log'))
    if ($simulationText -match '\*\* (Error|Fatal)|FAIL' -or $simulationText -notmatch 'PASS tb_shared_ddr_720p') {
        throw 'Simulation ended without the required PASS summary.'
    }
    Get-Content (Join-Path $logRoot 'simulation.log')
}
finally {
    Pop-Location
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if (!$resolvedTestRoot.StartsWith($tempBase+'\',[StringComparison]::OrdinalIgnoreCase) -or
        ([IO.Path]::GetFileName($resolvedTestRoot) -notmatch '^shared_ddr_720p_[0-9a-f]{32}$')) {
        throw 'Refusing cleanup outside the named temporary test directory.'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
