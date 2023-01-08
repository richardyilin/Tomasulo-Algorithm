`ifndef __RESERVATIONSTATIONCOMMON_SV__
`define __RESERVATIONSTATIONCOMMON_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
`include "../rtl/common/BitOperation.sv"
module ReservationStationCommon#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter NUM_OPERAND = 1,
	parameter NUM_RESERVATION_STATION = 5,
	parameter BW_TAG = 2
)(
	input clk,
	input rst_n,

//----------From Instruction Queue----------
	`twowire_input(i_iq),
	input [2*BW_TAG-1:0] i_iq_Q_flatten,
	input signed [2*BW_PROCESSOR_DATA-1:0] i_iq_V_flatten,
	input [BW_TAG-1:0] i_iq_tag,
	input i_iq_speculation,

//----------Speculation----------
	`onewire_input(i_branch),
	input i_branch_correct_prediction,

//----------From Common Data Bus----------
	`onewire_input(i_cdb),
	input [BW_TAG-1:0] i_cdb_tag,
	input signed [BW_PROCESSOR_DATA-1:0] i_cdb_data,

//----------To Execution----------
	`twowire_output(o_exe),
	output logic [BW_TAG-1:0] o_exe_tag,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_exe_V_flatten,

	output logic [NUM_RESERVATION_STATION-1:0] i_iq_load_in,
	output logic [NUM_RESERVATION_STATION-1:0] o_exe_selected,
	output logic rsv_cen

);
logic [BW_TAG-1:0] i_iq_Q[2];
logic signed [BW_PROCESSOR_DATA-1:0] i_iq_V[2];
logic signed [BW_PROCESSOR_DATA-1:0] o_exe_V[2];
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		i_iq_Q[i] = i_iq_Q_flatten[i*BW_TAG +: BW_TAG];
		i_iq_V[i] = i_iq_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA];
		o_exe_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_exe_V[i];
	end
end

logic [NUM_RESERVATION_STATION-1:0] o_valid;
logic [NUM_RESERVATION_STATION-1:0] i_valid[2];
logic [BW_PROCESSOR_DATA-1:0] i_Q [2][NUM_RESERVATION_STATION][NUM_OPERAND], o_Q [NUM_RESERVATION_STATION][NUM_OPERAND];
logic signed [BW_PROCESSOR_DATA-1:0] i_V [2][NUM_RESERVATION_STATION][NUM_OPERAND], o_V [NUM_RESERVATION_STATION][NUM_OPERAND];
logic [BW_TAG-1:0] i_tag [NUM_RESERVATION_STATION], o_tag[NUM_RESERVATION_STATION];
logic [NUM_RESERVATION_STATION-1:0] o_ready;
logic [NUM_RESERVATION_STATION:0] o_exe_selected_extended;
logic o_exe_cen, i_iq_cen;
logic [NUM_RESERVATION_STATION:0] i_iq_selected_extended;
logic [NUM_RESERVATION_STATION-1:0] i_iq_selected;
logic [NUM_RESERVATION_STATION-1:0] i_available;
logic [NUM_RESERVATION_STATION-1:0] i_speculation, o_speculation;
logic rsv_valid_cen;
logic rsv_operand_cen;


FindFromLsb #(.N(NUM_RESERVATION_STATION)
) u_iq_select (
	.i_data(i_available),
	.o_cumsum(),
	.o_position(i_iq_selected_extended)
);
RoundRobin#(
	.NUM_CANDIDATE(NUM_RESERVATION_STATION)
) u_round_robin (
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(o_ready),
	.o_chosen(o_exe_selected_extended),
	.i_handshake(o_exe_cen)
);
assign o_exe_cen = `handshake(o_exe);
assign i_iq_cen = `handshake(i_iq);
assign rsv_cen = i_iq_cen;
assign rsv_operand_cen =  i_iq_cen || i_cdb_valid;
assign rsv_valid_cen = i_iq_cen || o_exe_cen; // add input, remove the output

always@(*) begin
	o_exe_tag = 'd0;
	for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
		o_exe_tag = o_exe_tag | (o_exe_selected[i] ? o_tag[i] : 'd0);
	end
	for (int i = 0; i < NUM_OPERAND; i++) begin
		o_exe_V[i] = 'd0;
		for (int j = 0; j < NUM_RESERVATION_STATION; j++) begin
			o_exe_V[i] = o_exe_V[i] | ((o_exe_selected[j]) ? o_V[j][i] : 'd0);
		end
	end
end
always @(*) begin
	for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
		o_ready[i] = o_valid[i];
		for (int j = 0; j < NUM_OPERAND; j++) begin
			o_ready[i] = o_ready[i] && (o_Q[i][j] == 'd0) && !o_speculation[i];
		end
	end
	o_exe_selected = o_exe_selected_extended[NUM_RESERVATION_STATION-1:0];
	o_exe_valid = !o_exe_selected_extended[NUM_RESERVATION_STATION];
	i_valid[0] = o_valid & ~(o_exe_selected & {(NUM_RESERVATION_STATION){o_exe_cen}}); // remove the selected one
	i_available = ~i_valid[0];
	i_iq_ready = !i_iq_selected_extended[NUM_RESERVATION_STATION]; // ready if there is a spot
	i_iq_selected = i_iq_selected_extended[NUM_RESERVATION_STATION-1:0];
	i_iq_load_in = i_iq_selected & {(NUM_RESERVATION_STATION){i_iq_cen}}; // todo: do not need &
	i_valid[1] = (i_valid[0] | i_iq_load_in) & (~(({(NUM_RESERVATION_STATION){i_branch_valid && !i_branch_correct_prediction}}) & o_speculation)); // add the input
	i_speculation = (o_speculation | (i_iq_load_in & {(NUM_RESERVATION_STATION){i_iq_speculation}})) & {(NUM_RESERVATION_STATION){!i_branch_valid}};
	for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin // add input
		i_tag[i] = i_iq_load_in[i] ? i_iq_tag : o_tag[i];
		for (int j = 0; j < NUM_OPERAND; j++) begin
			i_Q[0][i][j] = i_iq_load_in[i] ? i_iq_Q[j] : o_Q[i][j];
			i_V[0][i][j] = i_iq_load_in[i] ? i_iq_V[j] : o_V[i][j];
		end
	end
	for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin // check cdb
		for (int j = 0; j < NUM_OPERAND; j++) begin
			if (i_cdb_valid && i_Q[0][i][j] == i_cdb_tag) begin
				i_Q[1][i][j] = 'd0;
				i_V[1][i][j] = i_cdb_data;
			end else begin
				i_Q[1][i][j] = i_Q[0][i][j];
				i_V[1][i][j] = i_V[0][i][j];
			end
		end
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
			o_tag[i] <= 'd0;
		end
	end else if (rsv_cen) begin
		for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
			o_tag[i] <= i_tag[i];
		end
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
			for (int j = 0; j < NUM_OPERAND; j++) begin
				o_Q[i][j] <= 'd0;
				o_V[i][j] <= 'd0;
			end
		end
	end else if (rsv_operand_cen) begin
		for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
			for (int j = 0; j < NUM_OPERAND; j++) begin
				o_Q[i][j] <= i_Q[1][i][j];
				o_V[i][j] <= i_V[1][i][j];
			end
		end
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_valid <= 'd0;
	end else if (rsv_valid_cen || i_branch_valid) begin
		o_valid <= i_valid[1];
	end
end
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		i_iq_Q[i] = i_iq_Q_flatten[i*BW_TAG +: BW_TAG];
		i_iq_V[i] = i_iq_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA];
		o_exe_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_exe_V[i];
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		o_speculation <= 'd0;
	end else if (i_iq_cen || i_branch_valid) begin
		o_speculation <= i_speculation;
	end
end
endmodule
`endif