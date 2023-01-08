`ifndef __MEMORYUNIT_SV__
`define __MEMORYUNIT_SV__

`include "../rtl/common/Define.sv"
module MemoryUnit#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter NUM_LOAD_RESERVATION_STATION = 5,
	parameter NUM_STORE_RESERVATION_STATION = 5,
	parameter AQ_LENGTH = 10,
	parameter BW_TAG = 1,
	parameter BW_ADDRESS = 32
)(
	input clk,
	input rst_n,
//----------From Instruction Queue----------
	`twowire_input(i_lsrsv),
	input i_lsrsv_opcode, // r = 0, w = 1
	input [BW_TAG-1:0] i_lsrsv_tag,
	input [BW_ADDRESS-1:0] i_lsrsv_rwaddr,
	input signed [BW_PROCESSOR_DATA-1:0] i_lsrsv_wdata,

//----------To Data Memory----------
	`twowire_output(o_D_mem),
	input signed [BW_PROCESSOR_DATA-1:0] o_D_mem_rdata,
	output logic o_D_mem_r0w1, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] o_D_mem_rwaddr,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_D_mem_wdata,

//----------To CDB broadcast load----------
	`twowire_output(o_cdb),
	output logic [BW_TAG-1:0] o_cdb_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_cdb_data
);

logic cen_D_mem;
Pipeline u_pl1(
	.clk(clk),
	.rst(rst_n),
	`twowire_connect(i, i_lsrsv),
	.i_cen(cen_D_mem),
	`twowire_connect(o, o_D_mem)
);

`twowire_logic(i_pl2);
logic cen_cdb;
assign i_pl2_valid = o_D_mem_ready && (!o_D_mem_r0w1);
Pipeline u_pl2(
	.clk(clk),
	.rst(rst_n),
	`twowire_connect(i, i_pl2),
	.i_cen(cen_cdb),
	`twowire_connect(o, o_cdb)
);

logic [BW_TAG-1:0] s1_tag;
logic i_D_mem_r0w1;
assign i_D_mem_r0w1 = i_lsrsv_opcode == `STORE;

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_D_mem_r0w1 <= 1'b0;
		o_D_mem_rwaddr <= 'd0;
		o_D_mem_wdata <= 'd0;
		s1_tag <= 'd0;
	end else if (cen_D_mem) begin
		o_D_mem_r0w1 <= i_D_mem_r0w1;
		o_D_mem_rwaddr <= i_lsrsv_rwaddr;
		o_D_mem_wdata <= i_lsrsv_wdata;
		s1_tag <= i_lsrsv_tag;
	end
end

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_cdb_tag <= 'd0;
		o_cdb_data <= 'd0;
	end else if (cen_cdb) begin
		o_cdb_tag <= s1_tag;
		o_cdb_data <= o_D_mem_rdata;
	end
end

endmodule
`endif