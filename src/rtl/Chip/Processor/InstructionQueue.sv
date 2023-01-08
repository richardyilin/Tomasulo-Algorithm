`ifndef __InstructionQueue_SV__
`define __InstructionQueue_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
module InstructionQueue#(
	parameter BW_PROCESSOR_BLOCK = 64,
	parameter BW_PROCESSOR_DATA = 32,
	parameter NUM_GLOBAL_HISTORY = 4,
	parameter IQ_LENGTH = 2,
	parameter NUM_KINDS_OF_RESERVATION_STATION = 5,
	parameter NUM_KINDS_OF_UNIT = 4,
	parameter BW_TAG = 1,
	parameter BW_OPCODE_INT = 4,
	parameter BW_OPCODE_BRANCH = 3,
	parameter BW_ADDRESS = 32,
	parameter NUM_FIFO_INPUT_ENTRY = BW_PROCESSOR_BLOCK / BW_PROCESSOR_DATA,
	parameter BW_PC_MOD = $clog2(NUM_FIFO_INPUT_ENTRY) + (NUM_FIFO_INPUT_ENTRY<=1)
)(
	input clk,
	input rst_n,

//----------From PC------------
	`twowire_input(i_pc),
	input [BW_PROCESSOR_BLOCK-1:0] i_pc_instruction_flatten,
	input [BW_ADDRESS-1:0] i_pc_pc,
	input [BW_PC_MOD-1:0] i_pc_pc_upperbound,
	input [NUM_GLOBAL_HISTORY-1:0] i_pc_global_history,
	input [BW_PROCESSOR_BLOCK-1:0] i_pc_pc_next_flatten,


//----------From Branch Unit------------
	`onewire_input(i_branch), // flush
	input i_branch_flush,

//----------From/To Register File------------
	`onewire_output(o_rf), // valid is asserted if write the tag to rd in register file
	// rs
	output logic [9:0] o_rf_rs_flatten,
	input [2*BW_TAG-1:0] i_rf_Q_flatten,
	input signed [2*BW_PROCESSOR_DATA-1:0] i_rf_V_flatten,
	//rd
	output logic [4:0] o_rf_rd,
	output logic [BW_TAG-1:0] o_rf_tag,
	output logic o_rf_speculation,

//----------To reservation stations of Integer Unit----------
	`twowire_output(o_int),
	output logic [BW_OPCODE_INT-1:0] o_int_opcode,
	output logic [2*BW_TAG-1:0] o_int_Q_flatten,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_int_V_flatten,
	output logic [BW_TAG-1:0] o_int_tag,
	output logic o_int_speculation,

//----------To reservation stations of Multiplier----------
	`twowire_output(o_mul),
	output logic [2*BW_TAG-1:0] o_mul_Q_flatten,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_mul_V_flatten,
	output logic [BW_TAG-1:0] o_mul_tag,
	output logic o_mul_speculation,

//----------To reservation stations of Branch----------
	`twowire_output(o_branch),
	output logic [BW_TAG-1:0] o_branch_tag,
	output logic [2*BW_TAG-1:0] o_branch_Q_flatten,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_branch_V_flatten,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_branch_imm,
	output logic [BW_OPCODE_BRANCH-1:0] o_branch_opcode,
	output logic [BW_ADDRESS-1:0] o_branch_PC,
	output logic [BW_ADDRESS-1:0] o_branch_PC_next,
	output logic [NUM_GLOBAL_HISTORY-1:0] o_branch_global_history,

//-----------To load store unit----------
	`twowire_output(o_lsu),
	output logic [BW_TAG-1:0] o_lsu_tag,
	output logic [2*BW_TAG-1:0] o_lsu_Q_flatten,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_lsu_V_flatten,
	output logic signed [11:0] o_lsu_imm,
	output logic o_lsu_speculation,
	output logic o_lsu_opcode // 1 is store, 0 is load
);

logic [4:0] o_rf_rs[2];
logic [BW_TAG-1:0] i_rf_Q[2];
logic [BW_PROCESSOR_DATA-1:0] i_rf_V[2];
logic [BW_TAG-1:0] o_int_Q[2];
logic [BW_PROCESSOR_DATA-1:0] o_int_V[2];
logic [BW_TAG-1:0] o_mul_Q[2];
logic [BW_PROCESSOR_DATA-1:0] o_mul_V[2];
logic [BW_TAG-1:0] o_branch_Q[2];
logic [BW_PROCESSOR_DATA-1:0] o_branch_V[2];
logic [BW_TAG-1:0] o_lsu_Q[2];
logic [BW_PROCESSOR_DATA-1:0] o_lsu_V[2];
logic [BW_PROCESSOR_DATA-1:0] i_instruction[NUM_FIFO_INPUT_ENTRY];
logic [BW_ADDRESS-1:0] i_pc_pc_next[NUM_FIFO_INPUT_ENTRY];
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		o_rf_rs_flatten[i*5 +: 5] = o_rf_rs[i];
		i_rf_Q[i] = i_rf_Q_flatten[i*BW_TAG +: BW_TAG];
		i_rf_V[i] = i_rf_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA];
	end
end
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		o_int_Q_flatten[i*BW_TAG +: BW_TAG] = o_int_Q[i];
		o_int_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_int_V[i];
	end
	for (int i = 0; i < 2; i++) begin
		o_mul_Q_flatten[i*BW_TAG +: BW_TAG] = o_mul_Q[i];
		o_mul_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_mul_V[i];
	end
	for (int i = 0; i < 2; i++) begin
		o_branch_Q_flatten[i*BW_TAG +: BW_TAG] = o_branch_Q[i];
		o_branch_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_branch_V[i];
	end
	for (int i = 0; i < 2; i++) begin
		o_lsu_Q_flatten[i*BW_TAG +: BW_TAG] = o_lsu_Q[i];
		o_lsu_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_lsu_V[i];
	end
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		i_instruction[i] = i_pc_instruction_flatten[i*BW_ADDRESS +: BW_ADDRESS];
		i_pc_pc_next[i] = i_pc_pc_next_flatten[i*BW_ADDRESS +: BW_ADDRESS];
	end
end
localparam BW_FIFO = BW_PROCESSOR_DATA + 2 * BW_ADDRESS + NUM_GLOBAL_HISTORY;

`twowire_logic(o_fifo);
logic [BW_ADDRESS-1:0] i_pc[NUM_FIFO_INPUT_ENTRY];
logic [IQ_LENGTH-1:0] fifo_load_in[NUM_FIFO_INPUT_ENTRY];
logic [IQ_LENGTH-2:0] fifo_forward;
logic [BW_FIFO-1:0] queue [IQ_LENGTH], queue_w [NUM_FIFO_INPUT_ENTRY+1][IQ_LENGTH];
logic [BW_FIFO-1:0] i_fifo_data[NUM_FIFO_INPUT_ENTRY];
logic [BW_PROCESSOR_DATA-1:0] o_instruction;
logic [$clog2(IQ_LENGTH)-1:0] fifo_write_ptr;
logic [BW_PC_MOD-1:0] pc_mod_select; // assume we jump to 0x04, PC will still send the inst of PC = 0X0 and 0X4, but we can only take the inst of PC = 0x4
assign pc_mod_select = i_pc_pc[BW_PC_MOD+2-1:2];

`twowire_logic(i_whisper);
MultiInputFifoController #( // can take NUM_FIFO_INPUT_ENTRY inputs at one time, but only output one output at one time
	.N(IQ_LENGTH),
	.NUM_FIFO_INPUT_ENTRY(NUM_FIFO_INPUT_ENTRY), // The number of input the FIFO can take at one time
	.BW_PC_MOD(BW_PC_MOD)
) u_iq(
	.clk(clk),
	.rst_n(rst_n),

	`twowire_connect(i, i_pc),
	`twowire_connect(o, i_whisper),
	.i_flush(i_branch_flush),
	.i_pc_mod_select(pc_mod_select),
	.i_pc_upperbound(i_pc_pc_upperbound),
	.write_ptr(fifo_write_ptr),
	.o_forward(fifo_forward)
);
always @(*) begin
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		if (`handshake(i_pc) && (i >= pc_mod_select) && (i <= i_pc_pc_upperbound)) begin
			fifo_load_in[i] = 'd1 << (i + fifo_write_ptr - pc_mod_select);
		end else begin
			fifo_load_in[i] = 'd0;
		end
	end
	for (int i = 0; i < IQ_LENGTH-1; i++) begin
		queue_w[0][i] = fifo_forward[i] ? queue[i+1] : queue[i];
	end
	queue_w[0][IQ_LENGTH-1] = queue[IQ_LENGTH-1];
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		i_pc[i] = ({i_pc_pc[BW_ADDRESS-1:BW_PC_MOD+2], {(BW_PC_MOD){1'b0}}} + i) << 2;
		i_fifo_data[i] = {i_pc_global_history, i_instruction[i], i_pc_pc_next[i], i_pc[i]};
		for (int j = 0; j < IQ_LENGTH; j++) begin
			queue_w[i+1][j] = fifo_load_in[i][j] ? i_fifo_data[i] : queue_w[i][j];
		end
	end
end

`twowires_logic(o_whisper, NUM_KINDS_OF_UNIT);

logic [NUM_KINDS_OF_UNIT-1:0] o_mask;
logic [$clog2(NUM_KINDS_OF_UNIT)-1:0] o_unit_opcode;
logic o_speculation;
logic i_speculation[2];
assign o_mask = 'd1 << o_unit_opcode;

PipelineWhisper #(
	.DIM(NUM_KINDS_OF_UNIT)
) u_whisper (
	.i_target(o_mask),
	`twowire_connect(i, i_whisper),
	`twowire_connect(o, o_whisper)
);

assign o_whisper_ready[`LOAD_STORE] = o_lsu_ready;
assign o_lsu_valid = o_whisper_valid[`LOAD_STORE];
assign o_whisper_ready[`MUL] = o_mul_ready;
assign o_mul_valid = o_whisper_valid[`MUL];
assign o_whisper_ready[`BRANCH] = o_branch_ready;
assign o_branch_valid = o_whisper_valid[`BRANCH];
assign o_whisper_ready[`INT] = o_int_ready;
assign o_int_valid = o_whisper_valid[`INT];

logic [BW_TAG-1:0] o_tag, i_tag;

logic [6:0] opcode;
logic [2:0] funct3;
logic [6:0] funct7;

assign {o_branch_global_history, o_instruction, o_branch_PC_next, o_branch_PC} = queue[0];
assign funct3 = o_instruction[14:12];
assign funct7 = o_instruction[31:25];
assign opcode = o_instruction[6:0];
assign o_rf_rs[0] = o_instruction[19:15];
assign o_rf_rs[1] = o_instruction[24:20];
assign o_rf_rd = o_instruction[11:7];
assign o_rf_tag = o_tag;

assign o_int_tag = o_tag;
assign o_mul_tag = o_tag;
assign o_branch_tag = o_tag;
assign o_lsu_tag = o_tag;

assign o_int_speculation = o_speculation;
assign o_mul_speculation = o_speculation;
assign o_lsu_speculation = o_speculation;

always @(*) begin //decode
	o_int_opcode = `ADD;
	o_unit_opcode = `INT;
	o_rf_valid = 1'b0; // not write rd
	o_branch_imm = {{21{o_instruction[31]}}, o_instruction[7], o_instruction[30:25], o_instruction[11:8], 1'b0};
	o_branch_opcode = `BEQ;
	o_lsu_imm = o_instruction[31:20]; // load
	o_lsu_opcode = `LOAD;
	i_speculation[0] = o_speculation;
	for (int i = 0; i < 2; i++) begin
		o_mul_Q[i] = i_rf_Q[i];
		o_mul_V[i] = i_rf_V[i];
		o_lsu_Q[i] = i_rf_Q[i];
		o_lsu_V[i] = i_rf_V[i];
		o_int_Q[i] = i_rf_Q[i];
		o_int_V[i] = i_rf_V[i];
		o_branch_Q[i] = i_rf_Q[i];
		o_branch_V[i] = i_rf_V[i];
	end
	if (o_tag == '1) begin
		i_tag = 'd1;
	end else begin
		i_tag = o_tag + 'd1;
	end
	case (opcode)
		7'b0110011: begin // R-type
			o_rf_valid = `handshake(i_whisper);
			if (funct7[0]) begin // mul or div
				o_unit_opcode = `MUL;
			end else begin
				case (funct3)
					3'b000: begin
						if (funct7[5]) begin
							o_int_opcode = `MINUS;
						end else begin
							o_int_opcode = `ADD;
						end
					end
					3'b010: begin // SLT
						o_int_opcode = `SLT;
					end
					3'b100: begin // xor
						o_int_opcode = `XOR;
					end
					3'b110: begin // or
						o_int_opcode = `OR;
					end
					3'b111: begin // and
						o_int_opcode = `AND;
					end
				endcase
			end
		end
		7'b0010011: begin // i type
			o_rf_valid = `handshake(i_whisper);
			o_int_Q[1] = 'd0;
			o_int_V[1] = {{20{o_instruction[31]}}, o_instruction[31:20]};
			case (funct3)
				3'b000: begin // addi
					o_int_opcode = `ADD;
				end
				3'b001: begin// slli
					o_int_opcode = `SLLI;
					o_int_V[1] = o_instruction[24:20];
				end
				3'b010: begin // slti
					o_int_opcode = `SLT;
				end
				3'b100: begin // xori
					o_int_opcode = `XOR;
				end
				3'b101: begin
					if (funct7[5]) begin // SRAI
						o_int_opcode = `SRAI;
						o_int_V[1] = {{(BW_PROCESSOR_DATA-5){1'b0}} ,o_instruction[24:20]};
					end else begin // SRLI
						o_int_opcode = `SRLI;
						o_int_V[1] = {{(BW_PROCESSOR_DATA-5){1'b0}} ,o_instruction[24:20]};
					end
				end
				3'b110: begin // ori
					o_int_opcode = `OR;
				end
				3'b111: begin // andi
					o_int_opcode = `AND;
				end
			endcase
		end
		7'b0100011: begin //sw
			o_unit_opcode =  `LOAD_STORE;
			o_lsu_imm = {o_instruction[31:25], o_instruction[11:7]};
			o_lsu_opcode = `STORE;
		end
		7'b0000011: begin // lw
			o_rf_valid = `handshake(i_whisper);
			o_unit_opcode =  `LOAD_STORE;
			o_lsu_imm = o_instruction[31:20]; // load
			o_lsu_opcode = `LOAD;
		end
		7'b1100011: begin // beq bne
			i_speculation[0] = 1'b1;
			o_unit_opcode =  `BRANCH;
			o_branch_imm = {{21{o_instruction[31]}}, o_instruction[7], o_instruction[30:25], o_instruction[11:8], 1'b0};
			case (funct3)
				3'b000: begin // beq
					o_branch_opcode = `BEQ;
				end
				3'b001: begin // bne
					o_branch_opcode = `BNE;
				end
				3'b101: begin // bge
					o_branch_opcode = `BGE;
				end
			endcase
		end
		7'b1100111: begin // jalr
			i_speculation[0] = 1'b1;
			o_rf_valid = `handshake(i_whisper);
			o_unit_opcode =  `BRANCH;
			o_branch_imm = {{20{o_instruction[31]}}, o_instruction[31:20]};
			o_branch_Q[1] = 'd0;
			o_branch_opcode = `JALR;
		end
		7'b1101111: begin // jal
			i_speculation[0] = 1'b1;
			o_rf_valid = `handshake(i_whisper);
			o_unit_opcode =  `BRANCH;
			o_branch_imm = {{11{o_instruction[31]}}, o_instruction[31], o_instruction[19:12], o_instruction[20], o_instruction[30:21], 1'b0};
			for (int i = 0; i < 2; i++) begin
				o_branch_Q[i] = 'd0;
			end
			o_branch_opcode = `JAL;
		end
		7'b0010111: begin // auipc
			o_rf_valid = `handshake(i_whisper);
			o_int_opcode = `AUIPC;
			o_int_Q[0] = 'd0;
			o_int_V[0] = o_branch_PC;
			o_int_Q[1] = 'd0;
			o_int_V[1] = {o_instruction[31:12], 12'b0};
		end
	endcase
	i_speculation[1] = i_speculation[0] && !i_branch_valid;
end
assign o_rf_speculation = o_speculation;
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_tag <= 'd1;
	end else if(`handshake(i_whisper)) begin
		o_tag <= i_tag;
	end
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < IQ_LENGTH; i++) begin
			queue[i] <= 'd0;
		end
	end else if(`handshake(i_pc) || `handshake(i_whisper)) begin
		for (int i = 0; i < IQ_LENGTH; i++) begin
			queue[i] <= queue_w[NUM_FIFO_INPUT_ENTRY][i];
		end
	end
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_speculation <= 'd0;
	end else if (i_branch_valid || `handshake(i_whisper)) begin
		o_speculation <= i_speculation[1];
	end
end

endmodule
`endif