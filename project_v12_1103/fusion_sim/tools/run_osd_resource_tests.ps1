param([string]$ModelSimBin = 'D:/modelsim/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$simTemp = [IO.Path]::GetTempPath()
$env:TEMP = $simTemp
$env:TMP = $simTemp
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('osd_resource_ascii_' + [Guid]::NewGuid().ToString('N'))
if ($tempRoot -match '[^\x00-\x7F]') { throw "ModelSim temp path must be ASCII: $tempRoot" }

# Keep the frozen equivalence source byte-for-byte intact. The temporary
# reference is independently adapted to the specified BRI/CON gain strings.
function Set-TempReferenceGainText([string]$folder) {
    $referencePath = Join-Path $folder 'video_status_osd_ref.v'
    $source = [IO.File]::ReadAllText($referencePath)
    $header = '    input  wire [7:0]  bin_threshold_active, edge_threshold_active,'
    if (-not $source.Contains($header)) { throw 'reference gain port insertion point missing' }
    $source = $source.Replace($header, $header + "`r`n    input  wire [7:0]  bright_gain_active, contrast_gain_active,")
    $source = $source.Replace('threshold_value = (mode == 2) ? bin_value : edge_value;',
                              'threshold_value = (mode == 2 || mode == 4) ? bin_value : edge_value;')
    $callArgs = 'bin_threshold_active, edge_threshold_active, threshold_edit_active,'
    if (-not $source.Contains($callArgs)) { throw 'reference gain mux insertion point missing' }
    $source = $source.Replace($callArgs,
        '(mode_active == 4) ? bright_gain_active : bin_threshold_active, (mode_active == 5) ? contrast_gain_active : edge_threshold_active, threshold_edit_active,')
    $polarRowCondition = "if (ENABLE_POLAR_STATUS && mode >= 4'd9 && mode <= 4'd12) begin"
    $firstPolarRow = $source.IndexOf($polarRowCondition)
    $secondPolarRow = $source.IndexOf($polarRowCondition, $firstPolarRow + $polarRowCondition.Length)
    if ($firstPolarRow -lt 0 -or $secondPolarRow -lt 0) { throw 'reference row-3 adaptation point missing' }
    $row3Replacement = @'
if (mode == 4'd4 || mode == 4'd5) begin
                        case (index)
                            0:text_char=(mode==4'd4)?"B":"C";
                            1:text_char=(mode==4'd4)?"R":"O";
                            2:text_char=(mode==4'd4)?"I":"N";
                            4:text_char="G"; 5:text_char="A"; 6:text_char="I"; 7:text_char="N";
                            8:text_char=":";
                            9:text_char=8'h30+(threshold_value/100);
                            10:text_char=8'h30+((threshold_value/10)%10);
                            11:text_char=8'h30+(threshold_value%10);
                            14:text_char="K"; 15:text_char="E"; 16:text_char="Y"; 17:text_char=":";
                            18:text_char=edit_value?"G":"M";
                            19:text_char=edit_value?"A":"O";
                            20:text_char=edit_value?"I":"D";
                            21:text_char=edit_value?"N":"E";
                            default:text_char=8'h20;
                        endcase
                    end else 
'@
    $source = $source.Insert($secondPolarRow, $row3Replacement)
    $oldFrameLabel = @'
                2'd1: begin
                    case (index)
                        0:text_char="F"; 1:text_char="R"; 2:text_char="A";
                        3:text_char="M"; 4:text_char="E"; 5:text_char=" ";
                        6:text_char="H"; 7:text_char="E"; 8:text_char="X";
                        9:text_char=":"; 10:text_char=" ";
                        default: if ((index >= 11) && (index <= 18)) begin
                            nibble = (frame_value >> ((18-index)*4)) & 4'hf;
                            if (nibble < 10) text_char = 8'h30 + nibble;
                            else            text_char = 8'h41 + nibble - 10;
                        end
                    endcase
                end
'@
    $newFrameLabel = @'
                2'd1: begin
                    case (index)
                        0:text_char="C"; 1:text_char="N"; 2:text_char="T";
                        3:text_char=":"; 4:text_char=" ";
                        default: if ((index >= 5) && (index <= 12)) begin
                            nibble = (frame_value >> ((12-index)*4)) & 4'hf;
                            if (nibble < 10) text_char = 8'h30 + nibble;
                            else            text_char = 8'h41 + nibble - 10;
                        end
                    endcase
                end
'@
    $oldFrameLabel = $oldFrameLabel.Replace("`r`n", "`n")
    $newFrameLabel = $newFrameLabel.Replace("`r`n", "`n")
    $source = $source.Replace("`r`n", "`n")
    if (-not $source.Contains($oldFrameLabel)) { throw 'temporary OSD reference FRAME HEX label adaptation point missing' }
    $source = $source.Replace($oldFrameLabel, $newFrameLabel)
    [IO.File]::WriteAllText($referencePath, $source, [Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $sources = @(
        '../user_source/osd/video_status_osd.v',
        '../user_source/osd/osd_char_lib.v',
        '../user_source/osd/anlogic_logo_rom.v',
        '../user_source/osd/anlogic_logo_sync_rom_direct.v',
        'sim/reference/resource_opt/video_status_osd_ref.v',
        'sim/tb_osd_resource_equiv.v'
    )
    foreach ($source in $sources) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $source) -Destination $tempRoot
    }
    Set-TempReferenceGainText $tempRoot
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'include_anchor') | Out-Null
    Push-Location $tempRoot
    try {
        $vlibOutput = & "$ModelSimBin/vlib.exe" work 2>&1
        if ($LASTEXITCODE -ne 0) { throw "vlib failed: $vlibOutput" }
        $compileOutput = & "$ModelSimBin/vlog.exe" '+incdir+include_anchor' @((Get-ChildItem -LiteralPath $tempRoot -Filter '*.v' | ForEach-Object FullName)) 2>&1
        $compileCode = $LASTEXITCODE
        $compileOutput | Out-File -LiteralPath (Join-Path $tempRoot 'compile.log') -Encoding ascii
        if ($compileCode -ne 0 -or (([string]::Join("`n",$compileOutput)) -match '\*\* (Error|Fatal)')) {
            throw "vlog failed (exit=$compileCode): $tempRoot/compile.log"
        }
        $simOutput = & "$ModelSimBin/vsim.exe" -c -onfinish exit tb_osd_resource_equiv -do 'run -all; quit -f' 2>&1
        $simCode = $LASTEXITCODE
        $simText = [string]::Join("`n",$simOutput)
        $simOutput | Out-File -LiteralPath (Join-Path $tempRoot 'simulation.log') -Encoding ascii
        $simOutput | Where-Object { $_ -match 'PASS|Fatal|Error' }
        if ($simCode -ne 0 -or $simText -match '\*\* (Error|Fatal)' -or $simText -notmatch 'PASS tb_osd_resource_equiv') {
            throw "simulation failed (exit=$simCode): $tempRoot/simulation.log"
        }
        Write-Output "ModelSim logs: $tempRoot"
    } finally { Pop-Location }

    # Confirm the comparator catches a temporary one-pixel glyph-column error.
    $negativeRoot = Join-Path $tempRoot 'negative_control'
    New-Item -ItemType Directory -Path $negativeRoot | Out-Null
    foreach ($source in $sources) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $source) -Destination $negativeRoot
    }
    Set-TempReferenceGainText $negativeRoot
    $negativeDut = Join-Path $negativeRoot 'video_status_osd.v'
    $negativeText = [IO.File]::ReadAllText($negativeDut)
    $correctColumn = 'char_col = text_pixel_in_cell[3:0];'
    if (-not $negativeText.Contains($correctColumn)) { throw 'negative-control injection point missing' }
    $negativeText = $negativeText.Replace($correctColumn, 'char_col = text_pixel_in_cell[3:0] + 1''b1;')
    [IO.File]::WriteAllText($negativeDut, $negativeText, [Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Force -Path (Join-Path $negativeRoot 'include_anchor') | Out-Null
    Push-Location $negativeRoot
    try {
        $vlibOutput = & "$ModelSimBin/vlib.exe" work 2>&1
        if ($LASTEXITCODE -ne 0) { throw "negative-control vlib failed: $vlibOutput" }
        $compileOutput = & "$ModelSimBin/vlog.exe" '+incdir+include_anchor' @((Get-ChildItem -LiteralPath $negativeRoot -Filter '*.v' | ForEach-Object FullName)) 2>&1
        $compileCode = $LASTEXITCODE
        $compileOutput | Out-File -LiteralPath (Join-Path $negativeRoot 'compile.log') -Encoding ascii
        if ($compileCode -ne 0 -or (([string]::Join("`n",$compileOutput)) -match '\*\* (Error|Fatal)')) {
            throw "negative-control compile failed: $negativeRoot/compile.log"
        }
        $negativeOutput = & "$ModelSimBin/vsim.exe" -c -onfinish exit tb_osd_resource_equiv -do 'run -all; quit -f' 2>&1
        $negativeText = [string]::Join("`n",$negativeOutput)
        $negativeOutput | Out-File -LiteralPath (Join-Path $negativeRoot 'simulation.log') -Encoding ascii
        if ($negativeText -notmatch 'OSD mismatch') {
            throw "negative-control error was not detected (exit=$LASTEXITCODE): $negativeRoot/simulation.log"
        }
        Write-Output 'PASS negative-control: injected +1 glyph-column offset was detected by old/new comparison.'
    } finally { Pop-Location }
} catch {
    Write-Output "ModelSim workspace: $tempRoot"
    throw
}
