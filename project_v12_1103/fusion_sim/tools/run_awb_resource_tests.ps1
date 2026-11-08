param([string]$ModelSimBin = 'D:\modelsim\win64')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = Join-Path $env:TEMP ('awb_resource_opt_' + [Guid]::NewGuid().ToString('N'))
$logRoot = Join-Path $PSScriptRoot 'awb_resource'
New-Item -ItemType Directory -Force -Path $tempRoot,$logRoot | Out-Null

$cellModels = @(
    'C:/Users/shiping/Desktop/FPGA/TD/sim_release/common/al_map_basic.v',
    'C:/Users/shiping/Desktop/FPGA/TD/sim_release/common/al_map_adder.v',
    'C:/Users/shiping/Desktop/FPGA/TD/sim_release/common/al_map_lut.v'
)
$gate = Join-Path $repo '../user_source/ip_source/divider/divider_gate.v'
$helper = Join-Path $repo '../user_source/hdl_source/awb_gain_divider.v'
$awb = Join-Path $repo '../user_source/hdl_source/awb.v'
$baseline = Join-Path $repo 'sim/reference/resource_opt/awb_baseline.v'

$calBench = Join-Path $tempRoot 'tb_old_divider_calibration.v'
@'
`timescale 1ns/1ps
module tb_old_divider_calibration;
    reg clk=0,rst=1,start=0;
    reg [31:0] denominator=1;
    reg [47:0] numerator=0;
    wire [47:0] quotient;
    wire [31:0] remainder;
    wire done;
    integer cycle=0,start_cycle=-1,done_cycle=-1;
    always #5 clk=~clk;
    divider dut(.clk(clk),.rst(rst),.start(start),.denominator(denominator),.numerator(numerator),
                .quotient(quotient),.remainder(remainder),.done(done));
    always @(posedge clk) cycle=cycle+1;
    task launch;
        input [31:0] d;
        input [47:0] n;
        begin
            @(negedge clk); denominator=d;numerator=n;start=1;
            @(posedge clk); #2; start_cycle=cycle;start=0;
            while(done !== 1'b1) begin @(posedge clk); #2; end
            done_cycle=cycle;
            if(done_cycle-start_cycle != 49) begin
                $display("FAIL latency start_edge=%0d done_edge=%0d delta=%0d",start_cycle,done_cycle,done_cycle-start_cycle);
                $finish;
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        launch(32'd3,48'h123456789abc);
        if(quotient !== 48'h061172283394) begin $display("FAIL quotient=%h",quotient);$finish;end
        launch(32'd0,48'h123456789abc);
        if(quotient !== 48'hffffffffffff) begin $display("FAIL den0 quotient=%h",quotient);$finish;end
        $display("tb_old_divider_calibration PASS start-to-done=49-edge-intervals total=50th-edge den0=ffffffffffff");
        $finish;
    end
endmodule
'@ | Set-Content -Encoding ascii $calBench

function Invoke-Sim($Name, $Sources, [switch]$Formal) {
    $folder = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $folder 'include_anchor') | Out-Null
    Push-Location $folder
    try {
        & (Join-Path $ModelSimBin 'vlib.exe') work 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "vlib failed: $Name" }
        $vlogArgs = @('-work','work')
        if ($Formal) { $vlogArgs += '+define+FORMAL_VERIFICATION' }
        $compile = & (Join-Path $ModelSimBin 'vlog.exe') '+incdir+include_anchor' @vlogArgs @Sources 2>&1
        $compile | Set-Content -LiteralPath (Join-Path $logRoot "$Name.compile.log") -Encoding utf8
        if ($LASTEXITCODE -ne 0) { throw "vlog failed: $Name; see tools/awb_resource/$Name.compile.log" }
        $run = & (Join-Path $ModelSimBin 'vsim.exe') -c -onfinish exit -lib work $Name -do 'run -all; quit -f' 2>&1
        $run | Set-Content -LiteralPath (Join-Path $logRoot "$Name.log") -Encoding utf8
        $joined = $run -join "`n"
        if ($LASTEXITCODE -ne 0 -or $joined -match '\*\* (Error|Fatal)|FAIL|errors=[1-9]' -or $joined -notmatch 'PASS') {
            throw "vsim failed: $Name; see tools/awb_resource/$Name.log"
        }
        Write-Output ($joined | Select-String 'PASS|errors=0' | ForEach-Object Line)
    } finally { Pop-Location }
}

Invoke-Sim 'tb_old_divider_calibration' ($cellModels + @($gate,$calBench)) -Formal
Invoke-Sim 'tb_awb_gain_divider' @($helper,(Join-Path $repo 'sim/tb_awb_gain_divider.v'))
Invoke-Sim 'tb_awb_real_equiv' ($cellModels + @($gate,$helper,$awb,$baseline,(Join-Path $repo 'sim/tb_awb_real_equiv.v'))) -Formal
Invoke-Sim 'tb_polar_awb' @($awb,(Join-Path $repo 'sim/tb_polar_awb.v'))
