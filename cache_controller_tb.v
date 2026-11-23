`timescale 1ns/1ps
module cache_controller_tb;
    parameter ADDR_W = 16, DATA_W = 32, MEM_LAT = 3;

    reg                clk = 0, rst_n = 0;
    reg                cpu_req = 0, cpu_we = 0;
    reg  [ADDR_W-1:0]  cpu_addr = 0;
    reg  [DATA_W-1:0]  cpu_wdata = 0;
    wire [DATA_W-1:0]  cpu_rdata;
    wire               cpu_ready;
    wire               mem_req, mem_we;
    wire [ADDR_W-1:0]  mem_addr;
    wire [DATA_W-1:0]  mem_wdata;
    reg  [DATA_W-1:0]  mem_rdata = 0;
    reg                mem_ready = 0;
    wire [31:0]        hit_count, miss_count;

    cache_controller dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .hit_count(hit_count), .miss_count(miss_count)
    );

    always #5 clk = ~clk;

    // Main memory model
    reg [DATA_W-1:0] mem [0:65535];
    integer k, cnt = 0;
    initial for (k = 0; k < 65536; k = k + 1) mem[k] = 32'hA000_0000 + k;

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_req && !mem_ready) begin
            cnt <= cnt + 1;
            if (cnt == MEM_LAT-1) begin
                cnt <= 0;
                mem_ready <= 1'b1;
                if (mem_we) mem[mem_addr] <= mem_wdata;
                else        mem_rdata     <= mem[mem_addr];
            end
        end else if (!mem_req) cnt <= 0;
    end

    integer errors = 0;

    task cpu_access(input we, input [ADDR_W-1:0] a, input [DATA_W-1:0] d);
        begin
            @(posedge clk);
            cpu_req <= 1; cpu_we <= we; cpu_addr <= a; cpu_wdata <= d;
            @(posedge clk);
            cpu_req <= 0;
            while (!cpu_ready) @(posedge clk);
        end
    endtask

    task check_read(input [ADDR_W-1:0] a, input [DATA_W-1:0] exp, input [127:0] name);
        begin
            cpu_access(0, a, 0);
            if (cpu_rdata !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s: addr=%h got=%h exp=%h", name, a, cpu_rdata, exp);
            end else
                $display("PASS %0s: addr=%h data=%h", name, a, cpu_rdata);
        end
    endtask

    task check_mem(input [ADDR_W-1:0] a, input [DATA_W-1:0] exp, input [127:0] name);
        begin
            if (mem[a] !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s: mem[%h]=%h exp=%h", name, a, mem[a], exp);
            end else
                $display("PASS %0s: mem[%h]=%h", name, a, mem[a]);
        end
    endtask

    initial begin
        $dumpfile("cache_tb.vcd");
        $dumpvars(0, cache_controller_tb);
        #22 rst_n = 1;

        check_read(16'h0010, 32'hA0000010, "read miss");
        check_read(16'h0010, 32'hA0000010, "read hit");
        cpu_access(1, 16'h0010, 32'hDEADBEEF);
        check_mem (16'h0010, 32'hA0000010, "wb deferred");
        check_read(16'h0010, 32'hDEADBEEF, "read after write");
        check_read(16'h0410, 32'hA0000410, "conflict miss");
        check_mem (16'h0010, 32'hDEADBEEF, "dirty evicted");
        cpu_access(1, 16'h0020, 32'h12345678);
        check_mem (16'h0020, 32'hA0000020, "mem unchanged");
        check_read(16'h0020, 32'h12345678, "read after wr-miss");
        check_read(16'h0420, 32'hA0000420, "evict dirty 2");
        check_mem (16'h0020, 32'h12345678, "dirty evicted 2");
        check_read(16'h0010, 32'hDEADBEEF, "refetch");

        $display("Hits=%0d (exp 4)  Misses=%0d (exp 5)", hit_count, miss_count);
        if (hit_count !== 4 || miss_count !== 5) errors = errors + 1;

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end
endmodule