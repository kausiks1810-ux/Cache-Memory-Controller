// Direct-mapped, write-back, write-allocate cache controller
// 1 word per line, word-addressed. 64 lines, 16-bit address.
module cache_controller #(
    parameter ADDR_W  = 16,
    parameter DATA_W  = 32,
    parameter INDEX_W = 6,
    parameter TAG_W   = ADDR_W - INDEX_W
)(
    input  wire                clk,
    input  wire                rst_n,

    // CPU side
    input  wire                cpu_req,
    input  wire                cpu_we,
    input  wire [ADDR_W-1:0]   cpu_addr,
    input  wire [DATA_W-1:0]   cpu_wdata,
    output reg  [DATA_W-1:0]   cpu_rdata,
    output reg                 cpu_ready,

    // Memory side
    output reg                 mem_req,
    output reg                 mem_we,
    output reg  [ADDR_W-1:0]   mem_addr,
    output reg  [DATA_W-1:0]   mem_wdata,
    input  wire [DATA_W-1:0]   mem_rdata,
    input  wire                mem_ready,

    output reg  [31:0]         hit_count,
    output reg  [31:0]         miss_count
);
    localparam LINES = (1 << INDEX_W);

    reg [DATA_W-1:0] data_arr  [0:LINES-1];
    reg [TAG_W-1:0]  tag_arr   [0:LINES-1];
    reg              valid_arr [0:LINES-1];
    reg              dirty_arr [0:LINES-1];

    localparam S_IDLE=3'd0, S_COMPARE=3'd1, S_WB=3'd2, S_ALLOC=3'd3;

    reg [2:0]        state;
    reg [ADDR_W-1:0] l_addr;
    reg              l_we;
    reg [DATA_W-1:0] l_wdata;
    reg              was_miss;

    wire [INDEX_W-1:0] idx = l_addr[INDEX_W-1:0];
    wire [TAG_W-1:0]   tag = l_addr[ADDR_W-1:INDEX_W];
    wire hit = valid_arr[idx] && (tag_arr[idx] == tag);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;  cpu_ready <= 0;  cpu_rdata <= 0;
            mem_req <= 0;  mem_we <= 0;  mem_addr <= 0;  mem_wdata <= 0;
            hit_count <= 0;  miss_count <= 0;  was_miss <= 0;
            for (i = 0; i < LINES; i = i + 1) begin
                valid_arr[i] <= 0;  dirty_arr[i] <= 0;
                tag_arr[i]   <= 0;  data_arr[i]  <= 0;
            end
        end else begin
            cpu_ready <= 1'b0;
            case (state)
                S_IDLE: begin
                    mem_req <= 1'b0;
                    if (cpu_req) begin
                        l_addr <= cpu_addr;  l_we <= cpu_we;
                        l_wdata <= cpu_wdata;  was_miss <= 1'b0;
                        state <= S_COMPARE;
                    end
                end

                S_COMPARE: begin
                    if (hit) begin
                        if (l_we) begin
                            data_arr[idx]  <= l_wdata;
                            dirty_arr[idx] <= 1'b1;
                        end else
                            cpu_rdata <= data_arr[idx];
                        if (!was_miss) hit_count <= hit_count + 1;
                        cpu_ready <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        miss_count <= miss_count + 1;
                        was_miss <= 1'b1;
                        if (valid_arr[idx] && dirty_arr[idx]) begin
                            mem_req <= 1;  mem_we <= 1;
                            mem_addr <= {tag_arr[idx], idx};
                            mem_wdata <= data_arr[idx];
                            state <= S_WB;
                        end else begin
                            mem_req <= 1;  mem_we <= 0;
                            mem_addr <= l_addr;
                            state <= S_ALLOC;
                        end
                    end
                end

                S_WB: if (mem_ready) begin
                    mem_req <= 1;  mem_we <= 0;
                    mem_addr <= l_addr;
                    state <= S_ALLOC;
                end

                S_ALLOC: if (mem_ready) begin
                    data_arr[idx]  <= mem_rdata;
                    tag_arr[idx]   <= tag;
                    valid_arr[idx] <= 1'b1;
                    dirty_arr[idx] <= 1'b0;
                    mem_req <= 1'b0;
                    state <= S_COMPARE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
# Cache-Memory-Controller