`ifndef __CHIP_SV__
`define __CHIP_SV__

`include "../rtl/Chip/Processor.sv"
`include "../rtl/Chip/Cache.sv"
module Chip#(
	parameter BW_PROCESSOR_BLOCK = 64,
	parameter BW_PROCESSOR_DATA = 32,
	parameter NUM_GLOBAL_HISTORY = 4,
	parameter BW_SELECTED_PC = 4,
	parameter NUM_BTB = 6,
	parameter IQ_LENGTH = 10,
	parameter NUM_KINDS_OF_RESERVATION_STATION = 5,
	parameter NUM_KINDS_OF_UNIT = 4,
	parameter NUM_INT_RESERVATION_STATION = 1,
	parameter NUM_MUL_RESERVATION_STATION = 1,
	parameter NUM_LOAD_RESERVATION_STATION = 1,
	parameter NUM_STORE_RESERVATION_STATION = 1,
	parameter BW_TAG = 32,
	parameter BW_OPCODE_BRANCH = 3,
	parameter AQ_LENGTH = 10,
	parameter BW_OPCODE_INT = 4,
	parameter BW_ADDRESS = 32,
	`ifdef L2
	parameter L2_LATENCY = 3,
	parameter L2_ASSOCITIVITY = 4,
	parameter L2_NUM_SET = 16,
	parameter L2_BW_BLOCK = 128,
	`endif
	parameter L1_LATENCY = 4,
	parameter L1_ASSOCITIVITY = 2,
	parameter L1_NUM_SET = 256,
	parameter L1_BW_BLOCK = 128
)(
    
	input clk,
	input rst_n,

//----------for instruction memory------------
	input I_mem_ready,
	`ifdef L2
		input [L2_BW_BLOCK-1:0] I_mem_rdata,
	`else
		input [L1_BW_BLOCK-1:0] I_mem_rdata,
	`endif
    output logic I_mem_valid,
	output logic I_mem_r0w1, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] I_mem_rwaddr,
	`ifdef L2
		output logic signed [L2_BW_BLOCK-1:0] I_mem_wdata,
	`else
		output logic signed [L1_BW_BLOCK-1:0] I_mem_wdata,
	`endif

//----------for data memory------------
	input D_mem_ready,
	`ifdef L2
		input [L2_BW_BLOCK-1:0] D_mem_rdata,
	`else
		input [L1_BW_BLOCK-1:0] D_mem_rdata,
	`endif
    output logic D_mem_valid,
	output logic D_mem_r0w1, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] D_mem_rwaddr,
	`ifdef L2
		output logic signed [L2_BW_BLOCK-1:0] D_mem_wdata,
	`else
		output logic signed [L1_BW_BLOCK-1:0] D_mem_wdata,
	`endif
//----------for testbench--------------
    output logic D_cache_wen,
    output logic [BW_ADDRESS-1:0] D_cache_addr,
    output logic signed [BW_PROCESSOR_DATA-1:0] D_cache_wdata
);

logic I_L1_valid;
logic I_L1_r0w1; // r = 0; w = 1
logic [BW_ADDRESS-1:0] I_L1_rwaddr;
logic [BW_PROCESSOR_BLOCK-1:0] I_L1_wdata;
logic I_L1_ready;
logic [BW_PROCESSOR_BLOCK-1:0] I_L1_rdata;

logic D_L1_valid;
logic D_L1_r0w1; // r = 0; w = 1
logic [BW_ADDRESS-1:0] D_L1_rwaddr;
logic [BW_PROCESSOR_DATA-1:0] D_L1_wdata;
logic D_L1_ready;
logic [BW_PROCESSOR_DATA-1:0] D_L1_rdata;

`ifdef L2
logic I_L2_valid;
logic I_L2_r0w1; // r = 0; w = 1
logic [BW_ADDRESS-1:0] I_L2_rwaddr;
logic [L1_BW_BLOCK-1:0] I_L2_wdata;
logic I_L2_ready;
logic [L1_BW_BLOCK-1:0] I_L2_rdata;

logic D_L2_valid;
logic D_L2_r0w1; // r = 0; w = 1
logic [BW_ADDRESS-1:0] D_L2_rwaddr;
logic [L1_BW_BLOCK-1:0] D_L2_wdata;
logic D_L2_ready;
logic [L1_BW_BLOCK-1:0] D_L2_rdata;
`endif

// // for testbed
// assign D_cache_wen = `handshake(D_L1) && D_L1_r0w1;
// assign D_cache_addr = D_L1_rwaddr;
// assign D_cache_wdata = D_L1_wdata;
// // end

Processor#(
	.BW_PROCESSOR_BLOCK(BW_PROCESSOR_BLOCK),
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_GLOBAL_HISTORY(NUM_GLOBAL_HISTORY),
	.BW_SELECTED_PC(BW_SELECTED_PC),
	.NUM_BTB(NUM_BTB),
	.IQ_LENGTH(IQ_LENGTH),
	.NUM_KINDS_OF_RESERVATION_STATION(NUM_KINDS_OF_RESERVATION_STATION),
	.NUM_KINDS_OF_UNIT(NUM_KINDS_OF_UNIT),
	.NUM_INT_RESERVATION_STATION(NUM_INT_RESERVATION_STATION),
	.NUM_MUL_RESERVATION_STATION(NUM_MUL_RESERVATION_STATION),
	.NUM_LOAD_RESERVATION_STATION(NUM_LOAD_RESERVATION_STATION),
	.NUM_STORE_RESERVATION_STATION(NUM_STORE_RESERVATION_STATION),
	.BW_TAG(BW_TAG),
	.BW_OPCODE_BRANCH(BW_OPCODE_BRANCH),
	.BW_OPCODE_INT(BW_OPCODE_INT),
	.BW_ADDRESS(BW_ADDRESS),
	.AQ_LENGTH(AQ_LENGTH)
) u_proc(
    
	.clk(clk),
	.rst_n(rst_n),

//----------for instruction memory------------
	.I_mem_ready(I_L1_ready),
	.I_mem_rdata(I_L1_rdata),
	.I_mem_valid(I_L1_valid),
	.I_mem_r0w1(I_L1_r0w1), // r = 0, w = 1
	.I_mem_rwaddr(I_L1_rwaddr),
	.I_mem_wdata(I_L1_wdata),

//----------for data memory------------
	.D_mem_ready(D_L1_ready),
	.D_mem_rdata(D_L1_rdata),
	.D_mem_valid(D_L1_valid),
	.D_mem_r0w1(D_L1_r0w1), // r = 0, w = 1
	.D_mem_rwaddr(D_L1_rwaddr),
	.D_mem_wdata(D_L1_wdata),
//----------for testbench--------------
	.D_cache_wen(D_cache_wen),
	.D_cache_addr(D_cache_addr),
	.D_cache_wdata(D_cache_wdata)
);

Cache #(
	.BW_ADDRESS(BW_ADDRESS),
	.LATENCY(L1_LATENCY),
	.ASSOCITIVITY(L1_ASSOCITIVITY),
	.NUM_SET(L1_NUM_SET),
	.BW_LAST_BLOCK(BW_PROCESSOR_BLOCK),
	.BW_BLOCK(L1_BW_BLOCK)
) u_I_L1 (
	// Interface for the last level (data requester or writer)
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(I_L1_valid),
	.i_r0w1(I_L1_r0w1), // r = 0, w = 1
	.i_rwaddr(I_L1_rwaddr),
	.i_wdata(I_L1_wdata),
	.i_ready(I_L1_ready),
	.i_rdata(I_L1_rdata),

	// interface for the next level
`ifdef L2
	.o_ready(I_L2_ready),
	.o_rdata(I_L2_rdata),
	.o_valid(I_L2_valid),
	.o_r0w1(I_L2_r0w1), // r = 0, w = 1
	.o_rwaddr(I_L2_rwaddr),
	.o_wdata(I_L2_wdata)
`else
	.o_ready(I_mem_ready),
	.o_rdata(I_mem_rdata),
	.o_valid(I_mem_valid),
	.o_r0w1(I_mem_r0w1), // r = 0, w = 1
	.o_rwaddr(I_mem_rwaddr),
	.o_wdata(I_mem_wdata)
`endif
);
Cache #(
	.BW_ADDRESS(BW_ADDRESS),
	.LATENCY(L1_LATENCY),
	.ASSOCITIVITY(L1_ASSOCITIVITY),
	.NUM_SET(L1_NUM_SET),
	.BW_LAST_BLOCK(BW_PROCESSOR_DATA),
	.BW_BLOCK(L1_BW_BLOCK)
) u_D_L1 (
	// Interface for the last level (data requester or writer)
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(D_L1_valid),
	.i_r0w1(D_L1_r0w1), // r = 0, w = 1
	.i_rwaddr(D_L1_rwaddr),
	.i_wdata(D_L1_wdata),
	.i_ready(D_L1_ready),
	.i_rdata(D_L1_rdata),

	// interface for the next level
`ifdef L2
	.o_ready(D_L2_ready),
	.o_rdata(D_L2_rdata),
	.o_valid(D_L2_valid),
	.o_r0w1(D_L2_r0w1), // r = 0, w = 1
	.o_rwaddr(D_L2_rwaddr),
	.o_wdata(D_L2_wdata)
`else
	.o_ready(D_mem_ready),
	.o_rdata(D_mem_rdata),
	.o_valid(D_mem_valid),
	.o_r0w1(D_mem_r0w1), // r = 0, w = 1
	.o_rwaddr(D_mem_rwaddr),
	.o_wdata(D_mem_wdata)
`endif
);

`ifdef L2
Cache #(
	.BW_ADDRESS(BW_ADDRESS),
	.LATENCY(L2_LATENCY),
	.ASSOCITIVITY(L2_ASSOCITIVITY),
	.NUM_SET(L2_NUM_SET),
	.BW_LAST_BLOCK(L1_BW_BLOCK),
	.BW_BLOCK(L2_BW_BLOCK)
) u_I_L2 (
	// Interface for the last level (data requester or writer)
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(I_L2_valid),
	.i_r0w1(I_L2_r0w1), // r = 0, w = 1
	.i_rwaddr(I_L2_rwaddr),
	.i_wdata(I_L2_wdata),
	.i_ready(I_L2_ready),
	.i_rdata(I_L2_rdata),

	.o_ready(I_mem_ready),
	.o_rdata(I_mem_rdata),
	.o_valid(I_mem_valid),
	.o_r0w1(I_mem_r0w1), // r = 0, w = 1
	.o_rwaddr(I_mem_rwaddr),
	.o_wdata(I_mem_wdata)
);
Cache #(
	.BW_ADDRESS(BW_ADDRESS),
	.LATENCY(L2_LATENCY),
	.ASSOCITIVITY(L2_ASSOCITIVITY),
	.NUM_SET(L2_NUM_SET),
	.BW_LAST_BLOCK(L1_BW_BLOCK),
	.BW_BLOCK(L2_BW_BLOCK)
) u_D_L2 (
	// Interface for the last level (data requester or writer)
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(D_L2_valid),
	.i_r0w1(D_L2_r0w1), // r = 0, w = 1
	.i_rwaddr(D_L2_rwaddr),
	.i_wdata(D_L2_wdata),
	.i_ready(D_L2_ready),
	.i_rdata(D_L2_rdata),

	// interface for the next level

	.o_ready(D_mem_ready),
	.o_rdata(D_mem_rdata),
	.o_valid(D_mem_valid),
	.o_r0w1(D_mem_r0w1), // r = 0, w = 1
	.o_rwaddr(D_mem_rwaddr),
	.o_wdata(D_mem_wdata)
);
`endif
endmodule
`endif