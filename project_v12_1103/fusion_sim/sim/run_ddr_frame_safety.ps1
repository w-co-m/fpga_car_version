param([string]$ModelSimBin = 'D:/modelsim/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ddr_frame_safety_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$rtl = @(
 'user/algorithms/reset_sync.v',
 'user/hdl_source/video_in.v','user/hdl_source/video_out.v','user/hdl_source/mc_to_user_interface.v',
 'user/ip_source/w128_d512_fifo/w128_d512_fifo.v','user/ip_source/w128_d512_fifo/soft_fifo_al_4057d6b76aa6.v',
 'user/ip_source/w155_d512_fifo/w155_d512_fifo.v','user/ip_source/w155_d512_fifo/soft_fifo_al_f58e8b3e1f3d.v')
foreach($item in $rtl) { Copy-Item -LiteralPath (Join-Path $projectRoot $item) -Destination $tempRoot }
Copy-Item -LiteralPath (Join-Path $projectRoot 'ddr_page_map.vh') -Destination $tempRoot
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'tb_ddr_frame_safety.v') -Destination $tempRoot
Push-Location $tempRoot
try {
 & "$ModelSimBin/vlib.exe" work | Out-Null
 if($LASTEXITCODE -ne 0) { throw 'vlib failed' }
 $sources = @(Get-ChildItem -LiteralPath $tempRoot -Filter '*.v' | ForEach-Object FullName)
 $compile = & "$ModelSimBin/vlog.exe" @sources 2>&1
 $compile | Set-Content (Join-Path $tempRoot 'compile.log') -Encoding utf8
 if($LASTEXITCODE -ne 0) { throw "compile failed: $tempRoot/compile.log" }
 $run = & "$ModelSimBin/vsim.exe" -c -onfinish exit tb_ddr_frame_safety -do 'run -all; quit -f' 2>&1
 $run | Set-Content (Join-Path $tempRoot 'run.log') -Encoding utf8
 $run
 if($LASTEXITCODE -ne 0 -or ($run -match '\*\* (Error|Fatal)|FAIL') -or !(($run -join "`n") -match 'PASS')) { throw "regression failed: $tempRoot/run.log" }
 Write-Output "Logs: $tempRoot"
} finally { Pop-Location }
