param([string]$ModelSimBin = 'D:/modelsim/win64')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logRoot = Join-Path $PSScriptRoot 'polar_cache'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('polar_cache_ascii_' + [Guid]::NewGuid().ToString('N'))
if ($tempRoot -match '[^\x00-\x7F]') { throw "ModelSim temp path must be ASCII: $tempRoot" }
New-Item -ItemType Directory -Force -Path $tempRoot,$logRoot | Out-Null
$sources = @(
    '../user_source/algorithms/algo_polar_core.v',
    '../user_source/algorithms/algo_fusion.v',
    '../user_source/algorithms/algo_polar_fusion.v',
    '../user_source/algorithms/line_buffer_3x3_sparse.v',
    '../user_source/algorithms/algo_edge_polar.v',
    '../user_source/algorithms/polar_block_engine.v',
    'sim/reference/resource_opt/polar_block_engine_ref.v',
    'sim/tb_polar_cache_equiv.v'
)
foreach ($source in $sources) { Copy-Item -LiteralPath (Join-Path $repo $source) -Destination $tempRoot }
Copy-Item -LiteralPath (Join-Path $repo '../user_source/ddr_page_map.vh') -Destination $tempRoot

# The frozen reference keeps grayscale AoP; stage an independent display oracle only in ASCII temp.
$stagedReference = Join-Path $tempRoot 'polar_block_engine_ref.v'
$referenceText = [IO.File]::ReadAllText($stagedReference)
$moduleMarker = "`r`n    localparam [3:0] ST_IDLE"
$paletteHelper = @'
    function [23:0] cache_palette_ref;
        input [7:0] a;
        integer segment,offset,fade;
        begin
            segment=a/43;offset=a-segment*43;fade=offset*6;
            case(segment)
                0:cache_palette_ref={8'd255,fade[7:0],8'd0};
                1:cache_palette_ref={8'd255-fade[7:0],8'd255,8'd0};
                2:cache_palette_ref={8'd0,8'd255,fade[7:0]};
                3:cache_palette_ref={8'd0,8'd255-fade[7:0],8'd255};
                4:cache_palette_ref={fade[7:0],8'd0,8'd255};
                default:cache_palette_ref={8'd255,8'd0,8'd255-fade[7:0]};
            endcase
        end
    endfunction
'@
$markerCount = [regex]::Matches($referenceText, [regex]::Escape($moduleMarker)).Count
if ($markerCount -ne 1) { throw "staged reference helper insertion count was $markerCount, expected 1" }
$referenceText = $referenceText.Replace($moduleMarker, "`r`n$paletteHelper`r`n    localparam [3:0] ST_IDLE")
$grayAop = 'aop_words<={aop_words[359:0],{3{fusion_aop}}};'
$colorAop = 'aop_words<={aop_words[359:0],cache_palette_ref(fusion_aop)};'
$aopCount = [regex]::Matches($referenceText, [regex]::Escape($grayAop)).Count
if ($aopCount -ne 1) { throw "staged reference AoP replacement count was $aopCount, expected 1" }
$referenceText = $referenceText.Replace($grayAop, $colorAop)
[IO.File]::WriteAllText($stagedReference, $referenceText, [Text.UTF8Encoding]::new($false))

function Invoke-PolarSim([string]$Folder, [string]$Label, [switch]$ExpectMismatch) {
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Folder 'include_anchor') | Out-Null
    Push-Location $Folder
    try {
        $lib = & (Join-Path $ModelSimBin 'vlib.exe') work 2>&1
        if ($LASTEXITCODE -ne 0) { throw "vlib failed for ${Label}: $($lib -join ' ')" }
        $files = @(Get-ChildItem -LiteralPath $Folder -Filter '*.v' | ForEach-Object FullName)
        $compile = & (Join-Path $ModelSimBin 'vlog.exe') '+incdir+include_anchor' -work work @files 2>&1
        $compileCode = $LASTEXITCODE
        [IO.File]::WriteAllLines((Join-Path $logRoot "$Label.compile.log"), [string[]]$compile, [Text.Encoding]::ASCII)
        $compileText = $compile -join "`n"
        if ($compileCode -ne 0 -or $compileText -match '\*\* (Error|Fatal)') { throw "vlog failed for $Label; see tools/polar_cache/$Label.compile.log" }
        $run = & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -lib work tb_polar_cache_equiv -do 'run -all; quit -f' 2>&1
        $runCode = $LASTEXITCODE
        [IO.File]::WriteAllLines((Join-Path $logRoot "$Label.log"), [string[]]$run, [Text.Encoding]::ASCII)
        $runText = $run -join "`n"
        if ($ExpectMismatch) {
            if ($runText -notmatch 'cycle mismatch|address mismatch|write data mismatch') { throw "negative control escaped comparator; see tools/polar_cache/$Label.log" }
            Write-Output 'PASS negative control: injected result-bank slice error was detected.'
        } elseif ($runCode -ne 0 -or $runText -match '\*\* (Error|Fatal)|FAIL' -or $runText -notmatch 'PASS tb_polar_cache_equiv') {
            throw "vsim failed for $Label (exit=$runCode); see tools/polar_cache/$Label.log"
        } else {
            $run | Where-Object { $_ -match 'PASS polar_cache_case|PASS tb_polar_cache_equiv' }
        }
    } finally { Pop-Location }
}

try {
    Invoke-PolarSim $tempRoot 'polar_cache_equiv'
    $negativeRoot = Join-Path $tempRoot 'negative_control'
    New-Item -ItemType Directory -Force -Path $negativeRoot | Out-Null
    foreach ($source in $sources) { Copy-Item -LiteralPath (Join-Path $tempRoot ([IO.Path]::GetFileName($source))) -Destination $negativeRoot }
    Copy-Item -LiteralPath (Join-Path $tempRoot 'ddr_page_map.vh') -Destination $negativeRoot
    $negativeDut = Join-Path $negativeRoot 'polar_block_engine.v'
    $negativeText = [IO.File]::ReadAllText($negativeDut)
    $pattern = '(expected_word\s*=\s*[A-Za-z0-9_]+\[)(\d+):(\d+)(\])'
    $slice = [regex]::Match($negativeText, $pattern)
    if ($slice.Success) {
        $high = [int]$slice.Groups[2].Value - 1
        $low = [int]$slice.Groups[3].Value - 1
        $replacement = "$($slice.Groups[1].Value)$high`:$low]"
        $negativeText = [regex]::Replace($negativeText, $pattern, $replacement, 1)
    } else {
        $pattern = 'assign\s+wr_data\s*=\s*expected_word\s*;'
        if ($negativeText -notmatch $pattern) { throw 'negative-control result-bank injection point is missing' }
        $negativeText = [regex]::Replace($negativeText, $pattern, "assign wr_data = expected_word ^ 128'd1;", 1)
    }
    [IO.File]::WriteAllText($negativeDut, $negativeText, [Text.UTF8Encoding]::new($false))
    Invoke-PolarSim $negativeRoot 'polar_cache_negative' -ExpectMismatch
    Write-Output "Permanent logs: $logRoot"
} catch {
    Write-Output "ASCII ModelSim workspace retained at: $tempRoot"
    throw
}

