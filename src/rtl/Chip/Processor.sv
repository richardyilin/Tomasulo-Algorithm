`ifndef __PROCESSOR_SV__
`define __PROCESSOR_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
`include "../rtl/Chip/Processor/PC.sv"
`include "../rtl/Chip/Processor/InstructionQueue.sv"
`include "../rtl/Chip/Processor/RegisterFile.sv"
`include "../rtl/Chip/Processor/ALUReservationStation.sv"
`include "../rtl/Chip/Processor/IntegerUnit.sv"
`include "../rtl/Chip/Processor/Multiplier.sv"
`include "../rtl/Chip/Processor/BranchUnit.sv"
`include "../rtl/Chip/Processor/CDB.sv"
`include "../rtl/Chip/Processor/LoadStoreUnit.sv"
module Processor#(
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
	parameter NUM_FIFO_INPUT_ENTRY = BW_PROCESSOR_BLOCK / BW_PROCESSOR_DATA,
	parameter BW_PC_MOD = $clog2(NUM_FIFO_INPUT_ENTRY) + (NUM_FIFO_INPUT_ENTRY<=1)
)(
    
	input clk,
	input rst_n,

//----------for instruction memory------------
	input I_mem_ready,
	input [BW_PROCESSOR_BLOCK-1:0] I_mem_rdata,
    output logic I_mem_valid,
	output logic I_mem_r0w1, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] I_mem_rwaddr,
	output logic [BW_PROCESSOR_BLOCK-1:0] I_mem_wdata,

//----------for data memory------------
	input D_mem_ready,
	input signed [BW_PROCESSOR_DATA-1:0] D_mem_rdata,
    output logic D_mem_valid,
	output logic D_mem_r0w1, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] D_mem_rwaddr,
	output logic signed [BW_PROCESSOR_DATA-1:0] D_mem_wdata,
//----------for testbench--------------
    output logic D_cache_wen,
    output logic [BW_ADDRESS-1:0] D_cache_addr,
    output logic signed [BW_PROCESSOR_DATA-1:0] D_cache_wdata
);
// for testbed
assign D_cache_wen = `handshake(D_mem) && D_mem_r0w1;
assign D_cache_addr = D_mem_rwaddr;
assign D_cache_wdata = D_mem_wdata;
// end
assign I_mem_r0w1 = 1'b0; // i cache is read only
`onewire_logic(pc_branch);
logic [BW_ADDRESS-1:0] pc_branch_pc;
logic [BW_ADDRESS-1:0] pc_branch_correct_pc_next;
logic [NUM_GLOBAL_HISTORY-1:0] pc_branch_global_history;
logic pc_branch_correct_prediction;

`twowire_logic(pc_iq);
logic [BW_PROCESSOR_BLOCK-1:0] pc_iq_instruction;
logic [BW_ADDRESS-1:0] pc_iq_pc;
logic [BW_PC_MOD-1:0] pc_iq_upperbound;
logic [BW_PROCESSOR_BLOCK-1:0] pc_iq_pc_next;
logic [NUM_GLOBAL_HISTORY-1:0] pc_iq_global_history;

PC#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_PROCESSOR_BLOCK(BW_PROCESSOR_BLOCK),
	.NUM_GLOBAL_HISTORY(NUM_GLOBAL_HISTORY),
	.BW_SELECTED_PC(BW_SELECTED_PC),
	.NUM_BTB(NUM_BTB),
	.BW_ADDRESS(BW_ADDRESS)
) u_pc (
	.clk(clk),
	.rst_n(rst_n),

//----------From Branch------------
	`onewire_connect(i_branch, pc_branch),
	.i_branch_pc(pc_branch_pc),
	.i_branch_correct_pc_next(pc_branch_correct_pc_next),
	.i_branch_global_history(pc_branch_global_history),
	.i_branch_correct_prediction(pc_branch_correct_prediction),

//----------To instruction memory------------
	//`twowire_connect(o_I_mem, I_mem),
	.o_I_mem_valid(I_mem_valid),
	.o_I_mem_ready(I_mem_ready),
	//.o_I_mem_ready(),
	.o_I_mem_rwaddr(I_mem_rwaddr),
	.i_I_mem_rdata(I_mem_rdata),

//----------To instruction queue------------
	`twowire_connect(o_iq, pc_iq),
	.o_iq_instruction_flatten(pc_iq_instruction),
	.o_iq_pc(pc_iq_pc),
	.o_iq_pc_upperbound(pc_iq_upperbound),
	.o_iq_pc_next_flatten(pc_iq_pc_next),
	.o_global_history(pc_iq_global_history)
);

`onewire_logic(iq_rf);
logic [9:0] iq_rf_rs;
logic [2*BW_TAG-1:0] iq_rf_Q;
logic signed [2*BW_PROCESSOR_DATA-1:0] iq_rf_V;
logic [4:0] iq_rf_rd;
logic [BW_TAG-1:0] iq_rf_tag;
logic iq_rf_speculation;

`onewire_logic(branch_iq);
logic branch_iq_flush;
// logic [BW_TAG-1:0] branch_iq_tag;

`twowire_logic(iq_int);
logic [BW_OPCODE_INT-1:0] iq_int_opcode;
logic [2*BW_TAG-1:0] iq_int_Q;
logic signed [2*BW_PROCESSOR_DATA-1:0] iq_int_V;
logic [BW_TAG-1:0] iq_int_tag;
logic iq_int_speculation;

`twowire_logic(iq_mul);
logic [2*BW_TAG-1:0] iq_mul_Q;
logic signed [2*BW_PROCESSOR_DATA-1:0] iq_mul_V;
logic [BW_TAG-1:0] iq_mul_tag;
logic iq_mul_speculation;

`twowire_logic(iq_br_rsv);
logic [BW_TAG-1:0] iq_br_rsv_tag;
logic [2*BW_TAG-1:0] iq_br_rsv_Q;
logic signed [2*BW_PROCESSOR_DATA-1:0] iq_br_rsv_V;
logic signed [BW_PROCESSOR_DATA-1:0] iq_br_rsv_imm;
logic [BW_OPCODE_BRANCH-1:0] iq_br_rsv_opcode;
logic [BW_ADDRESS-1:0] iq_br_rsv_PC;
logic [BW_ADDRESS-1:0] iq_br_rsv_PC_next;
logic [NUM_GLOBAL_HISTORY-1:0] iq_br_rsv_global_history;

`twowire_logic(iq_lsu);
logic [BW_TAG-1:0] iq_lsu_tag;
logic [2*BW_TAG-1:0] iq_lsu_Q;
logic signed [2*BW_PROCESSOR_DATA-1:0] iq_lsu_V;
logic signed [11:0] iq_lsu_imm;
logic iq_lsu_speculation;
logic iq_lsu_opcode;


InstructionQueue#(
	.BW_PROCESSOR_BLOCK(BW_PROCESSOR_BLOCK),
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.IQ_LENGTH(IQ_LENGTH),
	.NUM_GLOBAL_HISTORY(NUM_GLOBAL_HISTORY),
	.NUM_KINDS_OF_RESERVATION_STATION(NUM_KINDS_OF_RESERVATION_STATION),
	.NUM_KINDS_OF_UNIT(NUM_KINDS_OF_UNIT),
	.BW_TAG(BW_TAG),
	.BW_OPCODE_INT(BW_OPCODE_INT),
	.BW_OPCODE_BRANCH(BW_OPCODE_BRANCH),
	.BW_ADDRESS(BW_ADDRESS)
) u_iq (
	.clk(clk),
	.rst_n(rst_n),

//----------From PC------------
	`twowire_connect(i_pc, pc_iq),
	.i_pc_instruction_flatten(pc_iq_instruction),
	.i_pc_pc(pc_iq_pc),
	.i_pc_pc_upperbound(pc_iq_upperbound),
	.i_pc_global_history(pc_iq_global_history),
	.i_pc_pc_next_flatten(pc_iq_pc_next),

//----------From Branch Unit------------
	`onewire_connect(i_branch, branch_iq),
	.i_branch_flush(branch_iq_flush),

//----------From/To Register File------------
	`onewire_connect(o_rf, iq_rf),
	// rs
	.o_rf_rs_flatten(iq_rf_rs),
	.i_rf_Q_flatten(iq_rf_Q),
	.i_rf_V_flatten(iq_rf_V),
	//rd
	.o_rf_rd(iq_rf_rd),
	.o_rf_tag(iq_rf_tag),
	.o_rf_speculation(iq_rf_speculation),

//----------To reservation stations of Integer Unit----------
	`twowire_connect(o_int, iq_int),
	.o_int_opcode(iq_int_opcode),
	.o_int_Q_flatten(iq_int_Q),
	.o_int_V_flatten(iq_int_V),
	.o_int_tag(iq_int_tag),
	.o_int_speculation(iq_int_speculation),

//----------To reservation stations of Multiplier----------
	`twowire_connect(o_mul, iq_mul),
	.o_mul_Q_flatten(iq_mul_Q),
	.o_mul_V_flatten(iq_mul_V),
	.o_mul_tag(iq_mul_tag),
	.o_mul_speculation(iq_mul_speculation),

//----------To reservation stations of Branch----------
	`twowire_connect(o_branch, iq_br_rsv),
	.o_branch_tag(iq_br_rsv_tag),
	.o_branch_Q_flatten(iq_br_rsv_Q),
	.o_branch_V_flatten(iq_br_rsv_V),
	.o_branch_imm(iq_br_rsv_imm),
	.o_branch_opcode(iq_br_rsv_opcode),
	.o_branch_PC(iq_br_rsv_PC),
	.o_branch_PC_next(iq_br_rsv_PC_next),
	.o_branch_global_history(iq_br_rsv_global_history),

//----------To load store unit----------
	`twowire_connect(o_lsu, iq_lsu),
	.o_lsu_tag(iq_lsu_tag),
	.o_lsu_Q_flatten(iq_lsu_Q),
	.o_lsu_V_flatten(iq_lsu_V),
	.o_lsu_imm(iq_lsu_imm),
	.o_lsu_speculation(iq_lsu_speculation),
	.o_lsu_opcode(iq_lsu_opcode) // 1 is store, 0 is load
);

`twowire_logic(lsu_cdb);
logic [BW_TAG-1:0] lsu_cdb_tag;
logic [BW_PROCESSOR_DATA-1:0] lsu_cdb_wdata;
`onewire_logic(cdb_lsu);
logic [BW_TAG-1:0] cdb_lsu_tag;
logic signed [BW_PROCESSOR_DATA-1:0] cdb_lsu_data;
`onewire_logic(branch_int);
logic branch_int_correct_prediction;

`onewire_logic(branch_lsu);
logic branch_lsu_correct_prediction;

`onewire_logic(branch_rf);
logic branch_rf_correct_prediction;

`onewire_logic(branch_mul);
logic branch_mul_correct_prediction;
LoadStoreUnit#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_LOAD_RESERVATION_STATION(NUM_LOAD_RESERVATION_STATION),
	.NUM_STORE_RESERVATION_STATION(NUM_STORE_RESERVATION_STATION),
	.AQ_LENGTH(AQ_LENGTH),
	.BW_TAG(BW_TAG),
	.BW_ADDRESS(BW_ADDRESS)
) u_lsu (
	.clk(clk),
	.rst_n(rst_n),
	//----------From Instruction Queue----------
	`twowire_connect(i_iq, iq_lsu),
	.i_iq_tag(iq_lsu_tag),
	.i_iq_Q_flatten(iq_lsu_Q),
	.i_iq_V_flatten(iq_lsu_V),
	.i_iq_imm(iq_lsu_imm),
	.i_iq_opcode(iq_lsu_opcode),
	.i_iq_speculation(iq_lsu_speculation),

//----------Speculation----------
	`onewire_connect(i_branch, branch_lsu),
	.i_branch_correct_prediction(branch_lsu_correct_prediction),

//----------From Common Data Bus----------
	`onewire_connect(i_cdb, cdb_lsu),
	.i_cdb_tag(cdb_lsu_tag),
	.i_cdb_data(cdb_lsu_data),

//----------To Data Memory----------
	`twowire_connect(o_D_mem, D_mem),
	.o_D_mem_rdata(D_mem_rdata),
	.o_D_mem_r0w1(D_mem_r0w1), // r = 0, w = 1
	.o_D_mem_rwaddr(D_mem_rwaddr),
	.o_D_mem_wdata(D_mem_wdata),

//----------To CDB broadcast load----------
	`twowire_connect(o_cdb, lsu_cdb),
	.o_cdb_tag(lsu_cdb_tag),
	.o_cdb_data(lsu_cdb_wdata)
);

`onewire_logic(cdb_rf);
logic [BW_TAG-1:0] cdb_rf_tag;
logic signed [BW_PROCESSOR_DATA-1:0] cdb_rf_wdata;
RegisterFile#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_TAG(BW_TAG)
) u_rf (
	.clk(clk),
	.rst_n(rst_n),

//----------From/To Instruction Queue----------
	`onewire_connect(i_iq, iq_rf),
	// rs
	.i_iq_rs_flatten(iq_rf_rs),
	.o_iq_Q_flatten(iq_rf_Q),
	.o_iq_V_flatten(iq_rf_V),
	//rd
	.i_iq_rd(iq_rf_rd),
	.i_iq_tag(iq_rf_tag),
	.i_iq_speculation(iq_rf_speculation),

	`onewire_connect(i_branch, branch_rf),
	.i_branch_correct_prediction(branch_rf_correct_prediction),

//----------From CDB to future file----------
	`onewire_connect(i_cdb, cdb_rf),
	.i_cdb_tag(cdb_rf_tag),
	.i_cdb_wdata(cdb_rf_wdata)
);

`onewire_logic(cdb_int);
logic [BW_TAG-1:0] cdb_int_tag;
logic signed [BW_PROCESSOR_DATA-1:0] cdb_int_data;

`onewire_logic(cdb_mul);
logic [BW_TAG-1:0] cdb_mul_tag;
logic signed [BW_PROCESSOR_DATA-1:0] cdb_mul_data;

`onewire_logic(cdb_branch);
logic [BW_TAG-1:0] cdb_branch_tag;
logic signed [BW_PROCESSOR_DATA-1:0] cdb_branch_data;


`twowire_logic(int_rsv_exe);
logic [BW_OPCODE_INT-1:0] int_rsv_exe_opcode;
logic [BW_TAG-1:0] int_rsv_exe_tag;
logic signed [2*BW_PROCESSOR_DATA-1:0] int_rsv_exe_V;


ALUReservationStation#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_OPCODE_INT(BW_OPCODE_INT),
	.NUM_RESERVATION_STATION(NUM_INT_RESERVATION_STATION),
	.BW_TAG(BW_TAG)
) u_int (
	.clk(clk),
	.rst_n(rst_n),

//----------From Instruction Queue----------
	`twowire_connect(i_iq, iq_int),
	.i_iq_opcode(iq_int_opcode),
	.i_iq_Q_flatten(iq_int_Q),
	.i_iq_V_flatten(iq_int_V),
	.i_iq_tag(iq_int_tag),
	.i_iq_speculation(iq_int_speculation),

//----------Speculation----------
	`onewire_connect(i_branch, branch_mul),
	.i_branch_correct_prediction(branch_mul_correct_prediction),

//----------From Common Data Bus----------
	`onewire_connect(i_cdb, cdb_int),
	.i_cdb_tag(cdb_int_tag),
	.i_cdb_data(cdb_int_data),

//----------To Execution----------
	`twowire_connect(o_exe, int_rsv_exe),
	.o_exe_opcode(int_rsv_exe_opcode),
	.o_exe_tag(int_rsv_exe_tag),
	.o_exe_V_flatten(int_rsv_exe_V)
);

`twowire_logic(int_cdb);
logic [BW_TAG-1:0] int_cdb_tag;
logic signed [BW_PROCESSOR_DATA-1:0] int_cdb_wdata;
IntegerUnit#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_OPCODE_INT(BW_OPCODE_INT),
	.BW_TAG(BW_TAG)
) u_iu (
	.clk(clk),
	.rst_n(rst_n),

//----------From Reservation Station----------
	`twowire_connect(i_rsv, int_rsv_exe),
	.i_rsv_opcode(int_rsv_exe_opcode),
	.i_rsv_tag(int_rsv_exe_tag),
	.i_rsv_V_flatten(int_rsv_exe_V),

//----------To CDB----------
	`twowire_connect(o_cdb, int_cdb),
	.o_cdb_tag(int_cdb_tag),
	.o_cdb_wdata(int_cdb_wdata)
);

`twowire_logic(mul_rsv_exe);
logic [BW_TAG-1:0] mul_rsv_exe_tag;
logic signed [2*BW_PROCESSOR_DATA-1:0] mul_rsv_exe_V;

ALUReservationStation#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_RESERVATION_STATION(NUM_MUL_RESERVATION_STATION),
	.BW_OPCODE_INT(BW_OPCODE_INT),
	.BW_TAG(BW_TAG)
) u_mul (
	.clk(clk),
	.rst_n(rst_n),

//----------From Instruction Queue----------
	`twowire_connect(i_iq, iq_mul),
	.i_iq_opcode(),
	.i_iq_Q_flatten(iq_mul_Q),
	.i_iq_V_flatten(iq_mul_V),
	.i_iq_tag(iq_mul_tag),
	.i_iq_speculation(iq_mul_speculation),

//----------Speculation----------
	`onewire_connect(i_branch, branch_int),
	.i_branch_correct_prediction(branch_int_correct_prediction),

//----------From Common Data Bus----------
	`onewire_connect(i_cdb, cdb_mul),
	.i_cdb_tag(cdb_mul_tag),
	.i_cdb_data(cdb_mul_data),

//----------To Execution----------
	`twowire_connect(o_exe, mul_rsv_exe),
	.o_exe_opcode(),
	.o_exe_tag(mul_rsv_exe_tag),
	.o_exe_V_flatten(mul_rsv_exe_V)
);

`twowire_logic(mul_cdb);
logic [BW_TAG-1:0] mul_cdb_tag;
logic signed [BW_PROCESSOR_DATA-1:0] mul_cdb_wdata;
Multiplier#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_TAG(BW_TAG)
) u_mu (
	.clk(clk),
	.rst_n(rst_n),

//----------From Instruction Queue----------
	`twowire_connect(i_rsv, mul_rsv_exe),
	.i_rsv_tag(mul_rsv_exe_tag),
	.i_rsv_V_flatten(mul_rsv_exe_V),

//----------To CDB----------
	`twowire_connect(o_cdb, mul_cdb),
	.o_cdb_tag(mul_cdb_tag),
	.o_cdb_wdata(mul_cdb_wdata)
);

`twowire_logic(branch_cdb);
logic [BW_TAG-1:0] branch_cdb_tag;
logic [BW_ADDRESS-1:0] branch_cdb_address;
BranchUnit#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_GLOBAL_HISTORY(NUM_GLOBAL_HISTORY),
	.BW_TAG(BW_TAG),
	.BW_OPCODE_BRANCH(BW_OPCODE_BRANCH),
	.BW_ADDRESS(BW_ADDRESS)
) u_bu (
	.clk(clk),
	.rst_n(rst_n),

//----------From Instruction Queue----------
	`twowire_connect(i_iq, iq_br_rsv),
	.i_iq_tag(iq_br_rsv_tag),
	.i_iq_Q_flatten(iq_br_rsv_Q),
	.i_iq_V_flatten(iq_br_rsv_V),
	.i_iq_imm(iq_br_rsv_imm),
	.i_iq_opcode(iq_br_rsv_opcode),
	.i_iq_PC(iq_br_rsv_PC),
	.i_iq_PC_next(iq_br_rsv_PC_next),
	.i_iq_global_history(iq_br_rsv_global_history),

//----------From Common Data Bus----------
	`onewire_connect(i_cdb, cdb_branch),
	.i_cdb_tag(cdb_branch_tag),
	.i_cdb_data(cdb_branch_data),

//----------PC----------
	`onewire_connect(o_pc, pc_branch),
	.o_pc_pc(pc_branch_pc),
	.o_pc_correct_pc_next(pc_branch_correct_pc_next),
	.o_pc_correct_prediction(pc_branch_correct_prediction),
	.o_pc_global_history(pc_branch_global_history),

//----------To CDB----------
	`twowire_connect(o_cdb, branch_cdb),
	.o_cdb_tag(branch_cdb_tag),
	.o_cdb_address(branch_cdb_address), // jal, jalr needs to store PC+4 in cdb
// //----------To Instruction Queue (flush)----------
	`onewire_connect(o_iq, branch_iq),
	.o_iq_flush(branch_iq_flush),
	
	`onewire_connect(o_lsu, branch_lsu),
	.o_lsu_correct_prediction(branch_lsu_correct_prediction),
	
	
	`onewire_connect(o_int, branch_int),
	.o_int_correct_prediction(branch_int_correct_prediction),
	
	`onewire_connect(o_mul, branch_mul),
	.o_mul_correct_prediction(branch_mul_correct_prediction),

	`onewire_connect(o_rf, branch_rf),
	.o_rf_correct_prediction(branch_rf_correct_prediction)
);


CDB#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_TAG(BW_TAG),
	.NUM_KINDS_OF_RESERVATION_STATION(NUM_KINDS_OF_RESERVATION_STATION),
	.NUM_KINDS_OF_UNIT(NUM_KINDS_OF_UNIT),
	.BW_ADDRESS(BW_ADDRESS)
) u_cdb (
	.clk(clk),
	.rst_n(rst_n),


//----------From Integer Unit----------
	`twowire_connect(i_int, int_cdb),
	.i_int_tag(int_cdb_tag),
	.i_int_wdata(int_cdb_wdata),

//----------From Multiplier----------
	`twowire_connect(i_mul, mul_cdb),
	.i_mul_tag(mul_cdb_tag),
	.i_mul_wdata(mul_cdb_wdata),

//----------From Branch Unit----------
	`twowire_connect(i_branch, branch_cdb),
	.i_branch_tag(branch_cdb_tag),
	.i_branch_wdata(branch_cdb_address), // jal, jalr needs to store PC+4 in rd

//----------From Load Address Unit----------
	`twowire_connect(i_load, lsu_cdb),
	.i_load_tag(lsu_cdb_tag),
	.i_load_wdata(lsu_cdb_wdata),

//----------To Register File----------
	`onewire_connect(o_rf, cdb_rf),
	.o_rf_tag(cdb_rf_tag),
	.o_rf_data(cdb_rf_wdata),

//----------To Integer Unit----------
	`onewire_connect(o_int, cdb_int),
	.o_int_tag(cdb_int_tag),
	.o_int_data(cdb_int_data),

//----------To Multiplier----------
	`onewire_connect(o_mul, cdb_mul),
	.o_mul_tag(cdb_mul_tag),
	.o_mul_data(cdb_mul_data),

//----------To Load Store Unit----------
	`onewire_connect(o_lsu, cdb_lsu),
	.o_lsu_tag(cdb_lsu_tag),
	.o_lsu_data(cdb_lsu_data),

//----------To branch----------
	`onewire_connect(o_branch, cdb_branch),
	.o_branch_tag(cdb_branch_tag),
	.o_branch_data(cdb_branch_data)
);

endmodule
`endif