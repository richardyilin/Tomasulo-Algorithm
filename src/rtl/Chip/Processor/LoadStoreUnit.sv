`ifndef __LOADSTOREUNIT_SV__
`define __LOADSTOREUNIT_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
`include "../rtl/common/BitOperation.sv"
`include "../rtl/Chip/Processor/LoadStoreUnit/LoadStoreReservationStation.sv"
`include "../rtl/Chip/Processor/LoadStoreUnit/MemoryUnit.sv"
module LoadStoreUnit#(
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
	`twowire_input(i_iq),
	input [BW_TAG-1:0] i_iq_tag,
	input [2*BW_TAG-1:0] i_iq_Q_flatten,
	input signed [2*BW_PROCESSOR_DATA-1:0] i_iq_V_flatten,
	input signed [11:0] i_iq_imm,
	input i_iq_opcode, // 1 is store, 0 is load
	input i_iq_speculation,

//----------From Common Data Bus----------
	`onewire_input(i_cdb),
	input [BW_TAG-1:0] i_cdb_tag,
	input signed [BW_PROCESSOR_DATA-1:0] i_cdb_data,

//----------Speculation----------
	`onewire_input(i_branch),
	input i_branch_correct_prediction,

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

`twowire_logic(lsrsv_mu);
logic lsrsv_mu_opcode; // r = 0, w = 1
logic [BW_TAG-1:0] lsrsv_mu_tag;
logic [BW_ADDRESS-1:0] lsrsv_mu_rwaddr;
logic signed [BW_PROCESSOR_DATA-1:0] lsrsv_mu_wdata;

LoadStoreReservationStation#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_LOAD_RESERVATION_STATION(NUM_LOAD_RESERVATION_STATION),
	.NUM_STORE_RESERVATION_STATION(NUM_STORE_RESERVATION_STATION),
	.BW_TAG(BW_TAG),
	.BW_ADDRESS(BW_ADDRESS),
	.AQ_LENGTH(AQ_LENGTH)
) u_lsrsv (
	.clk(clk),
	.rst_n(rst_n),
	//----------From Instruction Queue----------
	`twowire_connect(i_iq, i_iq),
	.i_iq_tag(i_iq_tag),
	.i_iq_Q_flatten(i_iq_Q_flatten),
	.i_iq_V_flatten(i_iq_V_flatten),
	.i_iq_imm(i_iq_imm),
	.i_iq_opcode(i_iq_opcode),
	.i_iq_speculation(i_iq_speculation),

//----------Speculation----------
	`onewire_connect(i_branch, i_branch),
	.i_branch_correct_prediction(i_branch_correct_prediction),

//----------From Common Data Bus----------
	`onewire_connect(i_cdb, i_cdb),
	.i_cdb_tag(i_cdb_tag),
	.i_cdb_data(i_cdb_data),

//----------To Memory Unit----------
	`twowire_connect(o_mu, lsrsv_mu),
	.o_mu_opcode(lsrsv_mu_opcode), // r = 0, w = 1
	.o_mu_tag(lsrsv_mu_tag),
	.o_mu_rwaddr(lsrsv_mu_rwaddr),
	.o_mu_wdata(lsrsv_mu_wdata)
);

MemoryUnit#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_LOAD_RESERVATION_STATION(NUM_LOAD_RESERVATION_STATION),
	.NUM_STORE_RESERVATION_STATION(NUM_STORE_RESERVATION_STATION),
	.BW_TAG(BW_TAG),
	.BW_ADDRESS(BW_ADDRESS)
) u_mu (
	.clk(clk),
	.rst_n(rst_n),

//----------From LoadStoreReservationStation----------
	`twowire_connect(i_lsrsv, lsrsv_mu),
	.i_lsrsv_opcode(lsrsv_mu_opcode), // r = 0, w = 1
	.i_lsrsv_tag(lsrsv_mu_tag),
	.i_lsrsv_rwaddr(lsrsv_mu_rwaddr),
	.i_lsrsv_wdata(lsrsv_mu_wdata),
	
//----------To Data Memory----------
	`twowire_connect(o_D_mem, o_D_mem),
	.o_D_mem_rdata(o_D_mem_rdata),
	.o_D_mem_r0w1(o_D_mem_r0w1), // r = 0, w = 1
	.o_D_mem_rwaddr(o_D_mem_rwaddr),
	.o_D_mem_wdata(o_D_mem_wdata),
//----------To CDB broadcast load----------
	`twowire_connect(o_cdb, o_cdb),
	.o_cdb_tag(o_cdb_tag),
	.o_cdb_data(o_cdb_data)
);

endmodule
`endif