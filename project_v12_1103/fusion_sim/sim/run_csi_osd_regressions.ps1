param([string]$ModelSimBin = 'D:/modelsim/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('csi_osd_ascii_' + [Guid]::NewGuid().ToString('N'))
if ($tempRoot -match '[^\x00-\x7F]') { throw "ModelSim temp path must be ASCII: $tempRoot" }
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$cases = [ordered]@{
    tb_csi_abort_recovery = @('user/hdl_source/isp/csi_unpacket_2lane.v')
    tb_osd_dash = @('user/osd/osd_char_lib.v')
}
$failures = @()
foreach ($name in $cases.Keys) {
    $folder = Join-Path $tempRoot $name
    New-Item -ItemType Directory -Path $folder | Out-Null
    foreach ($source in $cases[$name]) { Copy-Item -LiteralPath (Join-Path $projectRoot $source) -Destination $folder }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$name.v") -Destination $folder
    Push-Location $folder
    try {
        $vlibOutput = & "$ModelSimBin/vlib.exe" work 2>&1
        if ($LASTEXITCODE -ne 0) { throw "vlib failed for $name`: $vlibOutput" }
        $rtl = @(Get-ChildItem -LiteralPath $folder -Filter '*.v' | ForEach-Object FullName)
        $compileOutput = & "$ModelSimBin/vlog.exe" @rtl 2>&1
        $compileCode = $LASTEXITCODE
        $compileOutput | Out-File -LiteralPath (Join-Path $folder 'compile.log') -Encoding ascii
        if ($compileCode -ne 0 -or (([string]::Join("`n",$compileOutput)) -match '\*\* (Error|Fatal)')) {
            $failures += "$name compile failed"
            $compileOutput
            continue
        }
        $simOutput = & "$ModelSimBin/vsim.exe" -c -onfinish exit $name -do 'run -all; quit -f' 2>&1
        $simCode = $LASTEXITCODE
        $simText = [string]::Join("`n",$simOutput)
        $simOutput | Out-File -LiteralPath (Join-Path $folder 'simulation.log') -Encoding ascii
        $simOutput | Where-Object { $_ -match 'CHECK|PASS|FAIL|Fatal|Error' }
        if ($simCode -ne 0 -or $simText -match '\*\* (Error|Fatal)' -or $simText -notmatch "PASS $name") {
            $failures += "$name simulation failed (exit=$simCode)"
        }
    } finally { Pop-Location }
}
Write-Output "ModelSim ASCII workspace: $tempRoot"
if ($failures.Count -gt 0) { throw ($failures -join '; ') }
Write-Output 'All assigned regressions passed.'
