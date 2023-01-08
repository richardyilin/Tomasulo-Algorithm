`ifndef __PC_SV__
`define __PC_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/Chip/Processor/PC/CorrelatingBranchPredictor.sv"
module PC#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_PROCESSOR_BLOCK = 64,
	parameter NUM_GLOBAL_HISTORY = 4,
	parameter BW_SELECTED_PC = 4,
	parameter NUM_BTB = 6,
	parameter BW_ADDRESS = 32,
	parameter NUM_FIFO_INPUT_ENTRY = BW_PROCESSOR_BLOCK / BW_PROCESSOR_DATA,
	parameter BW_PC_MOD = $clog2(NUM_FIFO_INPUT_ENTRY) + (NUM_FIFO_INPUT_ENTRY<=1)
)(
	input clk,
	input rst_n,

//----------From Branch------------
	`onewire_input(i_branch),
	input [BW_ADDRESS-1:0] i_branch_pc,
	input [BW_ADDRESS-1:0] i_branch_correct_pc_next,
	input [NUM_GLOBAL_HISTORY-1:0] i_branch_global_history,
	input i_branch_correct_prediction,

//----------To instruction memory------------
	`twowire_output(o_I_mem),
	output logic [BW_ADDRESS-1:0] o_I_mem_rwaddr,
	input [BW_PROCESSOR_BLOCK-1:0] i_I_mem_rdata,

//----------To instruction queue------------
	`twowire_output(o_iq),
	output logic [BW_PROCESSOR_BLOCK-1:0] o_iq_instruction_flatten,
	output logic [BW_ADDRESS-1:0] o_iq_pc,
	output logic [BW_PC_MOD-1:0] o_iq_pc_upperbound,
	output logic [BW_PROCESSOR_BLOCK-1:0] o_iq_pc_next_flatten,
	output logic [NUM_GLOBAL_HISTORY-1:0] o_global_history
);

localparam WAIT_I_MEM = 0;
localparam WAIT_IQ = 1;
localparam WAIT_I_MEM_MISPREDICT = 2;
logic [1:0] state, state_w;
logic [BW_ADDRESS-1:0] pc, pc_w; // pc is up to date pc, change when IQ get the pc or mispredict
logic [BW_ADDRESS-1:0] predicted_pc;
logic [BW_ADDRESS-1:0] o_I_mem_rwaddr_w; // o_I_mem_rwaddr may not be up to date because the value should not change during valid asserted, but change to predicted pc once handshke is done, or pc if mispredict
logic pc_cen, inst_cen, o_I_mem_rwaddr_cen;
logic [BW_PROCESSOR_BLOCK-1:0] inst, inst_w;
logic mispredict;
logic o_I_mem_valid_w;

`ifdef BRANCH_PREDICTION
CorrelatingBranchPredictor#(
	.NUM_GLOBAL_HISTORY(NUM_GLOBAL_HISTORY),
	.BW_SELECTED_PC(BW_SELECTED_PC),
	.NUM_BTB(NUM_BTB),
	.BW_PROCESSOR_BLOCK(BW_PROCESSOR_BLOCK),
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.BW_ADDRESS(BW_ADDRESS)
) u_branch_pred (
	.clk(clk),
	.rst_n(rst_n),

//----------From Branch------------
	`onewire_connect(i_branch, i_branch),
	.i_branch_pc(i_branch_pc),
	.i_branch_correct_pc_next(i_branch_correct_pc_next),
	.i_branch_global_history(i_branch_global_history),
	.i_branch_correct_prediction(i_branch_correct_prediction),

//----------To instruction memory------------
	.i_pc(pc),
	.o_predicted_pc_flatten(o_iq_pc_next_flatten),
	.o_predicted_pc(predicted_pc),
	.o_pc_upperbound(o_iq_pc_upperbound),
	.o_global_history(o_global_history)
);
`else
logic [BW_ADDRESS-1:0] o_predicted_pc[NUM_FIFO_INPUT_ENTRY];
always @(*) begin
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		o_predicted_pc[i] = ({pc[BW_ADDRESS-1:BW_PC_MOD+2], {(BW_PC_MOD){1'b0}}} + i) << 2;
		o_iq_pc_next_flatten[i*BW_ADDRESS +: BW_ADDRESS] = o_predicted_pc[i];
	end
end
assign o_iq_pc_upperbound = '1;
assign predicted_pc = ({pc[BW_ADDRESS-1:BW_PC_MOD+2], {(BW_PC_MOD){1'b0}}} + NUM_FIFO_INPUT_ENTRY)  << 2; // assume pc jumps to 0x4, next we still need to fetch 0x8 instead of 0xc, or the pc we give IQ would be wrong
`endif
assign mispredict = i_branch_valid && !i_branch_correct_prediction;
assign o_I_mem_rwaddr_cen = (!o_I_mem_valid || o_I_mem_ready); // modify here
assign pc_cen = mispredict || (o_iq_valid && o_iq_ready);

always@(*) begin
	state_w = state;
	o_I_mem_valid_w = 1'b0;
	o_iq_valid = 1'b0;
	pc_w = pc;
	inst_w = i_I_mem_rdata;
	inst_cen = 1'b0;
	o_I_mem_rwaddr_w = o_I_mem_rwaddr;
	o_iq_instruction_flatten = inst;
	o_iq_pc = pc;
	case (state)
		WAIT_I_MEM: begin
			o_I_mem_valid_w = 1'b1;
			if (mispredict) begin // mispredict
				pc_w = i_branch_correct_pc_next;
				if (o_I_mem_ready) begin
					state_w = WAIT_I_MEM;
					o_I_mem_rwaddr_w = i_branch_correct_pc_next;
				end else begin
					state_w = WAIT_I_MEM_MISPREDICT;
				end
			end else if (o_I_mem_ready) begin
				o_iq_valid = 1'b1;
				o_I_mem_rwaddr_w = predicted_pc;
				if (o_iq_ready) begin // forward
					o_iq_instruction_flatten = i_I_mem_rdata;
					pc_w = predicted_pc;
				end else begin
					state_w = WAIT_IQ;
					o_I_mem_valid_w = 1'b0;
					inst_cen = 1'b1;
				end
			end
		end
		WAIT_IQ: begin
			o_iq_valid = 1'b1;
			if (mispredict) begin // mispredict
				state_w = WAIT_I_MEM;
				pc_w = i_branch_correct_pc_next;
				o_I_mem_rwaddr_w = i_branch_correct_pc_next;
				o_I_mem_valid_w = 1'b1;
			end else if (o_iq_ready) begin
				state_w = WAIT_I_MEM;
				pc_w = predicted_pc;
				o_I_mem_rwaddr_w = predicted_pc; // modify here
				o_I_mem_valid_w = 1'b1;
			end
		end
		WAIT_I_MEM_MISPREDICT: begin
			o_I_mem_valid_w = 1'b1;
			if (o_I_mem_ready) begin
				state_w = WAIT_I_MEM;
				o_I_mem_rwaddr_w = pc;
			end
		end
		default: ;
	endcase
end

always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		pc <= 'd0;
	end else if (pc_cen) begin
		pc <= pc_w;
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		inst <= 'd0;
	end else if (inst_cen) begin
		inst <= inst_w;
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_I_mem_rwaddr <= 'd0;
	end else if (o_I_mem_rwaddr_cen) begin
		o_I_mem_rwaddr <= o_I_mem_rwaddr_w;
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state <= 'd0;
		o_I_mem_valid <= 1'b0;
	end else begin
		state <= state_w;
		o_I_mem_valid <= o_I_mem_valid_w;
	end
end
endmodule
`endif