`ifndef __MEMORY_SV__
`define __MEMORY_SV__


`include "../rtl/common/Define.sv"
module Memory#(
	parameter BW_ADDRESS = 32,
    parameter MEMORY_LATENCY = 4,
    parameter BW_LAST_BLOCK = 128,
	parameter MEMORY_SIZE = (1 << 12) * `BYTE
)(
    
	input clk,
    input rst_n,
	input i_valid,
	input i_r0w1, // r = 0, w = 1
	input [BW_ADDRESS-1:0] i_rwaddr,
	input  signed [BW_LAST_BLOCK-1:0] i_wdata,
	output logic o_ready,
	output logic signed [BW_LAST_BLOCK-1:0] o_rdata
);

    localparam NUM_BLOCK = MEMORY_SIZE / BW_LAST_BLOCK;
    localparam BW_INDEX = $clog2(NUM_BLOCK);
    localparam BW_OFFSET = $clog2(BW_LAST_BLOCK / `BYTE);

    localparam IDLE = 0; 
    localparam BUBBLE = 1; 
    localparam READY = 2; 

    logic [BW_LAST_BLOCK-1:0] memory [NUM_BLOCK], memory_w [NUM_BLOCK];
    logic [BW_INDEX-1:0] index;
    logic [2:0] state, state_w;

    logic [$clog2(MEMORY_LATENCY+1)-1:0] count, count_w;
	logic [BW_LAST_BLOCK-1:0] o_rdata_w;
    logic i_ready;

    assign index = i_rwaddr[BW_INDEX+BW_OFFSET-1:BW_OFFSET];
    //assign o_rdata = memory[index];

    always@(*) begin // FSM & control sig
        state_w = state;
        for (int i = 0; i < NUM_BLOCK; i++) begin
            memory_w[i] = memory[i];
        end
        count_w = count;
        o_rdata_w = o_rdata;
        i_ready = 1'b0;
        case(state)
            IDLE: begin
                i_ready = i_valid;
                if(i_valid) begin
                    if (MEMORY_LATENCY > 1) begin
                        state_w = BUBBLE;
                    end else begin
                        state_w = READY;
                    end
                    if (i_r0w1) begin
                        memory_w[index] = i_wdata;
                    end else begin
                        o_rdata_w = memory[index];
                    end
                end
            end
            BUBBLE: begin
                count_w = count + 'd1;
                if (count == MEMORY_LATENCY - 1) begin
                    state_w = READY;
                end
            end
            READY: begin
                state_w = IDLE;
                count_w = 'd0;                 
            end
            default:;
        endcase
    end
    always@( negedge clk) begin
        if (state == IDLE && i_valid && i_r0w1) begin
            for (int i = 0; i < NUM_BLOCK; i++) begin
                memory[i] <= memory_w[i];
            end
        end
    end

    always@( negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 'd0;
            count <= 'd0;
            o_rdata <= 'd0;
            o_ready <= 1'b0;
        end
        else begin
            state <= state_w;
            count <= count_w;
            o_rdata <= o_rdata_w;
            o_ready <= i_ready;
        end
    end
endmodule
`endif