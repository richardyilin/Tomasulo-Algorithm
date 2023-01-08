`ifndef __BranchUnit_SV__
`define __BranchUnit_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
module BranchUnit#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_TAG = 1,
	parameter BW_OPCODE_BRANCH = 3,
	parameter NUM_GLOBAL_HISTORY = 4,
	parameter BW_ADDRESS = 32
)(
	input clk,
	input rst_n,


//----------From Instruction Queue----------
	`twowire_input(i_iq),
	input [BW_TAG-1:0] i_iq_tag,
	input [2*BW_TAG-1:0] i_iq_Q_flatten,
	input signed [2*BW_PROCESSOR_DATA-1:0] i_iq_V_flatten,
	input signed [BW_PROCESSOR_DATA-1:0] i_iq_imm,
	input [BW_OPCODE_BRANCH-1:0] i_iq_opcode,
	input [BW_ADDRESS-1:0] i_iq_PC,
	input [BW_ADDRESS-1:0] i_iq_PC_next,
	input [NUM_GLOBAL_HISTORY-1:0] i_iq_global_history,

//----------From Common Data Bus----------
	`onewire_input(i_cdb),
	input [BW_TAG-1:0] i_cdb_tag,
	input [BW_PROCESSOR_DATA-1:0] i_cdb_data,

//----------PC----------
	`onewire_output(o_pc),
	output logic [BW_ADDRESS-1:0] o_pc_pc,
	output logic [BW_ADDRESS-1:0] o_pc_correct_pc_next,
	output logic [NUM_GLOBAL_HISTORY-1:0] o_pc_global_history,
	output logic o_pc_correct_prediction,

//----------To CDB----------
	`twowire_output(o_cdb),
	output logic [BW_TAG-1:0] o_cdb_tag,
	output logic [BW_ADDRESS-1:0] o_cdb_address, // jal, jalr needs to store PC+4 in rd
//----------To Instruction Queue and ROB (o_flush)----------
	`onewire_output(o_iq),
	output logic o_iq_flush,

//----------To Instruction Queue and ROB (o_flush)----------
	`onewire_output(o_lsu),
	output logic o_lsu_correct_prediction,

	`onewire_output(o_int),
	output logic o_int_correct_prediction,

	`onewire_output(o_mul),
	output logic o_mul_correct_prediction,

	`onewire_output(o_rf),
	output logic o_rf_correct_prediction

);

logic cdb_cen;
`twowire_logic(i_pl1);
Pipeline u_pl1(
	.clk(clk),
	.rst(rst_n),
	`twowire_connect(i, i_pl1),
	.i_cen(cdb_cen),
	`twowire_connect(o, o_cdb)
);
logic [BW_TAG-1:0] i_iq_Q[2];
logic signed [BW_PROCESSOR_DATA-1:0] i_iq_V[2];
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		i_iq_Q[i] = i_iq_Q_flatten[i*BW_TAG +: BW_TAG];
		i_iq_V[i] = i_iq_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA];
	end
end

localparam INIT = 0;
localparam COMPUTE = 1;
localparam WAIT_CDB = 2;

logic [1:0] state, state_w;
logic o_cdb_valid_w;
logic i_flush, o_flush;
logic [BW_TAG-1:0] o_Q[2], i_Q[2];
logic signed [BW_PROCESSOR_DATA-1:0] o_V[2], i_V[2];
logic [BW_TAG-1:0] o_tag;
logic signed [BW_PROCESSOR_DATA-1:0] o_imm;
logic [BW_OPCODE_BRANCH-1:0] o_opcode;
logic [BW_ADDRESS-1:0] o_pc_next;
logic i_ready;

logic [BW_ADDRESS-1:0] i_pc_pc;
logic [BW_ADDRESS-1:0] i_pc_correct_pc_next;
logic i_pc_correct_prediction;
logic [BW_ADDRESS-1:0] i_cdb_address;
logic o_cdb_broadcast;

logic i_pc_valid;

assign i_ready = i_Q[0] == 'd0 && i_Q[1] == 'd0;
assign o_rob_tag = o_tag;
assign i_pc_correct_prediction = i_pc_correct_pc_next == o_pc_next;
assign i_cdb_address = o_pc_pc + 'd4;
assign o_iq_valid = o_pc_valid;
assign o_lsu_valid = o_pc_valid;
assign o_int_valid = o_pc_valid;
assign o_mul_valid = o_pc_valid;
assign o_rf_valid = o_pc_valid;
assign o_iq_flush = o_flush;
assign o_lsu_correct_prediction = o_pc_correct_prediction;
assign o_int_correct_prediction = o_pc_correct_prediction;
assign o_mul_correct_prediction = o_pc_correct_prediction;
assign o_rf_correct_prediction = o_pc_correct_prediction;
always@(*) begin
	state_w = state;
	i_iq_ready = 1'b0;
	i_flush = 1'b0;
	i_pc_valid = 1'b0;
	i_pl1_valid = 1'b0;
	for (int j = 0; j < 2; j++) begin
		if (i_cdb_valid && o_Q[j] == i_cdb_tag) begin
			i_Q[j] = 'd0;
			i_V[j] = i_cdb_data;
		end else begin
			i_Q[j] = o_Q[j];
			i_V[j] = o_V[j];
		end
	end
	i_pc_correct_pc_next = o_pc_correct_pc_next;
	o_cdb_broadcast = 1'b0;
	case (o_opcode)
		`JAL: begin
			i_pc_correct_pc_next = o_pc_pc + o_imm;
			o_cdb_broadcast = 1'b1;
		end
		`JALR: begin
			i_pc_correct_pc_next = i_V[0] + o_imm;
			o_cdb_broadcast = 1'b1;
		end
		`BEQ: begin
			if (i_V[0] == i_V[1]) begin
				i_pc_correct_pc_next = o_pc_pc + o_imm;
			end else begin
				i_pc_correct_pc_next = o_pc_pc + 'd4;
			end
		end
		`BNE: begin
			if (i_V[0] != i_V[1]) begin
				i_pc_correct_pc_next = o_pc_pc + o_imm;
			end else begin
				i_pc_correct_pc_next = o_pc_pc + 'd4;
			end
		end
		`BGE: begin
			if (i_V[0] >= i_V[1]) begin
				i_pc_correct_pc_next = o_pc_pc + o_imm;
			end else begin
				i_pc_correct_pc_next = o_pc_pc + 'd4;
			end
		end
		default: ;
	endcase
	case (state)
		INIT: begin
			i_iq_ready = !o_pc_valid; // important, do not give IQ valid when the speculation is being resolved
			for (int j = 0; j < 2; j++) begin
				if (i_cdb_valid && i_iq_Q[j] == i_cdb_tag) begin
					i_Q[j] = 'd0;
					i_V[j] = i_cdb_data;
				end else begin
					i_Q[j] = i_iq_Q[j];
					i_V[j] = i_iq_V[j];
				end
			end
			if (i_iq_valid && !o_pc_valid) begin
				state_w = COMPUTE;
			end
		end
		COMPUTE: begin
			if (i_ready) begin
				i_pl1_valid = 1'b1;
				i_pc_valid = 1'b1;
				i_flush = !i_pc_correct_prediction;
				if (o_cdb_broadcast && !i_pl1_ready) begin // Only JAL and JALR needs to broadcast
					state_w = WAIT_CDB;
				end else begin
					state_w = INIT;
				end
			end
		end
		WAIT_CDB: begin
			i_pl1_valid = 1'b1;
			if (i_pl1_ready) begin
				state_w = INIT;
			end
		end
		default: ;
	endcase
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state <= 'd0;
	end else begin
		state <= state_w;
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_cdb_tag <= 'd0;
		o_cdb_address <= 'd0;
	end else if (cdb_cen) begin
		o_cdb_tag <= o_tag;
		o_cdb_address <= i_cdb_address;
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < 2; i++) begin
			o_Q[i] <= 'd0;
			o_V[i] <= 'd0;
		end
	end else if (i_iq_valid || i_cdb_valid) begin
		for (int i = 0; i < 2; i++) begin
			o_Q[i] <= i_Q[i];
			o_V[i] <= i_V[i];
		end
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_pc_correct_pc_next <= 'd0;
		o_pc_correct_prediction <= 1'b0;
	end else if (state == COMPUTE && i_ready) begin
		o_pc_correct_pc_next <= i_pc_correct_pc_next;
		o_pc_correct_prediction <= i_pc_correct_prediction;
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_flush <= 1'b0;
	end else if ((state == COMPUTE && i_ready) || o_flush) begin
		o_flush <= i_flush;
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_pc_valid <= 1'b0;
	end else if ((state == COMPUTE && i_ready) || o_pc_valid) begin
		o_pc_valid <= i_pc_valid;
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_tag <= 'd0;
		o_imm <= 'd0;
		o_opcode <= 'd0;
		o_pc_pc <= 'd0;
		o_pc_next <= 'd0;
		o_pc_global_history <= 'd0;
	end else if (state == INIT && i_iq_valid) begin // i_iq_ready is asserted only at the end, so it can not be handshake of iq
		o_tag <= i_iq_tag;
		o_imm <= i_iq_imm;
		o_opcode <= i_iq_opcode;
		o_pc_pc <= i_iq_PC;
		o_pc_next <= i_iq_PC_next;
		o_pc_global_history <= i_iq_global_history;
	end
end

endmodule
`endif