`ifndef __CORRELATINGBRANCHPREDICTOR_SV__
`define __CORRELATINGBRANCHPREDICTOR_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
module CorrelatingBranchPredictor#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter NUM_GLOBAL_HISTORY = 4,
	parameter BW_PROCESSOR_BLOCK = 64,
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
	input [BW_ADDRESS-1:0] i_pc,
	output logic [BW_ADDRESS-1:0] o_predicted_pc, // the next pc for module pc to fetch next time
	output logic [BW_PROCESSOR_BLOCK-1:0] o_predicted_pc_flatten,
	output logic [BW_PC_MOD-1:0] o_pc_upperbound,
	output [NUM_GLOBAL_HISTORY-1:0] o_global_history
);
// flatten
logic [BW_ADDRESS-1:0] predicted_pc[NUM_FIFO_INPUT_ENTRY];
always@(*) begin
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		o_predicted_pc_flatten[i*BW_ADDRESS +: BW_ADDRESS] = predicted_pc[i];
	end
end
//end flatten

// btb means branch target buffer
localparam NUM_GLOBAL_HISTORY_ENTRY = 1 << NUM_GLOBAL_HISTORY;
localparam NUM_LOCAL_HISTORY_ENTRY = 1 << BW_SELECTED_PC;
localparam BW_PREDICTOR = 2;
localparam STRONGLY_NOT_TAKEN = 0;
localparam WEAKLY_NOT_TAKEN = 1;
localparam WEAKLY_TAKEN = 2;
localparam STRONGLY_TAKEN = 3;

// Predicton part

logic [BW_ADDRESS-3:0] i_branch_pc_shift_right_by_2, i_branch_correct_pc_next_shift_right_by_2, i_pc_shift_right_by_2, o_predicted_pc_shift_right_by_2[NUM_FIFO_INPUT_ENTRY];
assign i_branch_pc_shift_right_by_2 = i_branch_pc >> 2; // last 2 bits of PC is the same (each instrution has 4 bytes)
assign i_branch_correct_pc_next_shift_right_by_2 = i_branch_correct_pc_next >> 2;
assign i_pc_shift_right_by_2 = i_pc >> 2;

assign o_global_history = global_history;

logic [NUM_GLOBAL_HISTORY-1:0] global_history, global_history_w;
logic [BW_SELECTED_PC-1:0] local_history[NUM_FIFO_INPUT_ENTRY];
logic [BW_PREDICTOR-1:0] predictors [NUM_GLOBAL_HISTORY_ENTRY][NUM_LOCAL_HISTORY_ENTRY];
logic [BW_PREDICTOR-1:0] predictor[NUM_FIFO_INPUT_ENTRY];
logic [NUM_FIFO_INPUT_ENTRY-1:0] predicted_taken;
logic [BW_ADDRESS-3:0] current_pc_shift_right_by_2[NUM_FIFO_INPUT_ENTRY];
logic [NUM_FIFO_INPUT_ENTRY-1:0] valid, prediction_taken_and_in_btb, valid_and_taken, selected_taken;
logic [NUM_FIFO_INPUT_ENTRY:0] selected_taken_extended;
logic [BW_PC_MOD-1:0] selected_taken_binary;
logic [BW_ADDRESS-1:0] selected_predicted_pc;

logic [BW_ADDRESS-3:0] btb_pc [NUM_BTB], btb_pc_w [NUM_BTB];
logic [BW_ADDRESS-3:0] btb_pc_prediction [NUM_BTB], btb_pc_prediction_w [NUM_BTB];
logic [NUM_BTB-1:0] btb_valid, btb_valid_w;

logic [BW_ADDRESS-3:0] btb_selected_pc_prediction[NUM_FIFO_INPUT_ENTRY];
logic [NUM_BTB-1:0] btb_selected_mask_prediction[NUM_FIFO_INPUT_ENTRY];
logic [NUM_FIFO_INPUT_ENTRY-1:0] btb_selected_prediction;
logic [BW_PC_MOD-1:0] pc_mod_select; // assume we jump to 0x04, PC will still send the inst of PC = 0X0 and 0X4, but we can only take the inst of PC = 0x4

FindFromLsb #(.N(NUM_FIFO_INPUT_ENTRY)
) u_iq_select_srsv (
	.i_data(valid_and_taken),
	.o_cumsum(),
	.o_position(selected_taken_extended)
);
Onehot2Binary #(
	.N(NUM_FIFO_INPUT_ENTRY)
) u_oh2b(
	.i(selected_taken),
	.o(selected_taken_binary)
);
assign pc_mod_select = i_pc[BW_PC_MOD+2-1:2];
always @(*) begin
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		current_pc_shift_right_by_2[i] = {i_pc_shift_right_by_2[BW_ADDRESS-3:BW_PC_MOD], {(BW_PC_MOD){1'b0}}} + i;
		local_history[i] = current_pc_shift_right_by_2[i][BW_SELECTED_PC-1:0] + i;
		predictor[i] = predictors[global_history][local_history[i]];
		predicted_taken[i] = predictor[i] == WEAKLY_TAKEN || predictor[i] == STRONGLY_TAKEN;
		for (int j = 0; j < NUM_BTB; j++) begin
			btb_selected_mask_prediction[i][j] = btb_valid[j] && (btb_pc[j] == current_pc_shift_right_by_2[i]);
		end
		btb_selected_prediction[i] = |btb_selected_mask_prediction[i];
		btb_selected_pc_prediction[i] = 'd0;
		for (int j = 0; j < NUM_BTB; j++) begin
			btb_selected_pc_prediction[i] = btb_selected_pc_prediction[i] | (btb_selected_mask_prediction[i][j] ? btb_pc_prediction[j] : 'd0);
		end
		prediction_taken_and_in_btb[i] = predicted_taken[i] && btb_selected_prediction[i];
		o_predicted_pc_shift_right_by_2[i] = (prediction_taken_and_in_btb[i]) ? btb_selected_pc_prediction[i] : current_pc_shift_right_by_2[i] + 'd1;
		predicted_pc[i] = o_predicted_pc_shift_right_by_2[i] << 2;
		valid[i] = i >= pc_mod_select;
		valid_and_taken[i] = valid[i] && prediction_taken_and_in_btb[i];
	end
	selected_taken = selected_taken_extended[NUM_FIFO_INPUT_ENTRY-1:0];
	selected_predicted_pc = 'd0;
	for (int i = 0; i < NUM_FIFO_INPUT_ENTRY; i++) begin
		selected_predicted_pc = selected_predicted_pc | (selected_taken[i] ? predicted_pc[i] : 'd0);
	end
	if (selected_taken_extended[NUM_FIFO_INPUT_ENTRY]) begin // no one is taken
		o_pc_upperbound = '1;
		o_predicted_pc = (current_pc_shift_right_by_2[0] + NUM_FIFO_INPUT_ENTRY) << 2;
	end else begin
		o_pc_upperbound = selected_taken_binary;
		o_predicted_pc = selected_predicted_pc;
	end
end

// Modify predictor part

logic cen;
logic correct_taken;
logic [NUM_BTB:0] btb_insert_pos_extended;
logic [NUM_BTB-1:0] btb_insert_pos;
logic insert_new_pc_in_btb;
logic [BW_PREDICTOR-1:0] predictors_w [NUM_GLOBAL_HISTORY_ENTRY][NUM_LOCAL_HISTORY_ENTRY];
logic [BW_PREDICTOR-1:0] predictor_w;
logic [NUM_BTB-1:0] correct_btb_selected_mask;


FindFromLsb #(.N(NUM_BTB)
) u_insert_pos (
	.i_data(~btb_valid),
	.o_cumsum(),
	.o_position(btb_insert_pos_extended)
);

always @(*) begin
	correct_taken = i_branch_correct_pc_next_shift_right_by_2 != (i_branch_pc_shift_right_by_2 + 'd1);
	global_history_w = {global_history[NUM_GLOBAL_HISTORY-2:0], correct_taken};
	btb_insert_pos = btb_insert_pos_extended[NUM_BTB-1:0];
	for (int i = 0; i < NUM_BTB; i++) begin
		correct_btb_selected_mask[i] = btb_valid[i] && (btb_pc[i] == i_branch_pc_shift_right_by_2) && (btb_pc_prediction[i] != i_branch_correct_pc_next_shift_right_by_2); // if the prediction is wrong and not because the predictor decide not take
	end
	insert_new_pc_in_btb = !(|correct_btb_selected_mask) && correct_taken; // if pc is not in btb and correct pc is not pc + 4, add it to btb
	btb_valid_w = btb_valid;
	for (int i = 0; i < NUM_BTB; i++) begin
		btb_pc_w[i] = btb_pc[i];
		btb_pc_prediction_w[i] = btb_pc_prediction[i];
	end

	for (int i = 0; i < NUM_BTB; i++) begin // remove incorrect prediction
		if (correct_btb_selected_mask[i] && !i_branch_correct_prediction) begin
			btb_valid_w[i] = 1'b0;
		end
	end
	for (int i = 0; i < NUM_BTB; i++) begin // insert new pc in btb
		if (insert_new_pc_in_btb && btb_insert_pos[i]) begin
			btb_valid_w[i] = 1'b1;
			btb_pc_w[i] = i_branch_pc_shift_right_by_2;
			btb_pc_prediction_w[i] = i_branch_correct_pc_next_shift_right_by_2;
		end
	end
end

logic [BW_PREDICTOR-1:0] prev_predictor;
logic [BW_SELECTED_PC-1:0] i_branch_local_history;
assign i_branch_local_history = i_branch_pc_shift_right_by_2[BW_SELECTED_PC-1:0];
always @(*) begin // correct predictors
	prev_predictor = predictors[i_branch_global_history][i_branch_local_history];
	predictor_w = prev_predictor;
	case (prev_predictor)
		STRONGLY_NOT_TAKEN: begin
			if (correct_taken) begin
				predictor_w = WEAKLY_NOT_TAKEN;
			end
		end
		WEAKLY_NOT_TAKEN: begin
			if (correct_taken) begin
				predictor_w = WEAKLY_TAKEN;
			end else begin
				predictor_w = STRONGLY_NOT_TAKEN;
			end
		end
		WEAKLY_TAKEN: begin
			if (correct_taken) begin
				predictor_w = STRONGLY_TAKEN;
			end else begin
				predictor_w = WEAKLY_NOT_TAKEN;
			end
		end
		STRONGLY_NOT_TAKEN: begin
			if (!correct_taken) begin
				predictor_w = WEAKLY_TAKEN;
			end
		end
		default: ;
	endcase
	for (int i = 0; i < NUM_GLOBAL_HISTORY_ENTRY; i++) begin
		for (int j = 0; j < NUM_LOCAL_HISTORY_ENTRY; j++) begin
			predictors_w[i][j] = predictors[i][j];
		end
	end
	predictors_w[i_branch_global_history][i_branch_local_history] = predictor_w;
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		global_history <= 'd0;
		btb_valid <= 'd0;
		for (int i = 0; i < NUM_BTB; i++) begin
			btb_pc[i] <= 'd0;
			btb_pc_prediction[i] <= 'd0;
		end
		for (int i = 0; i < NUM_GLOBAL_HISTORY_ENTRY; i++) begin
			for (int j = 0; j < NUM_LOCAL_HISTORY_ENTRY; j++) begin
				predictors[i][j] <= 'd0;
			end
		end
	end else if (i_branch_valid) begin
		global_history <= global_history_w;
		btb_valid <= btb_valid_w;
		for (int i = 0; i < NUM_BTB; i++) begin
			btb_pc[i] <= btb_pc_w[i];
			btb_pc_prediction[i] <= btb_pc_prediction_w[i];
		end
		for (int i = 0; i < NUM_GLOBAL_HISTORY_ENTRY; i++) begin
			for (int j = 0; j < NUM_LOCAL_HISTORY_ENTRY; j++) begin
				predictors[i][j] <= predictors_w[i][j];
			end
		end
	end
end

endmodule
`endif