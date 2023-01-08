`ifndef __ALURESERVATIONSTATION_SV__
`define __ALURESERVATIONSTATION_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
`include "../rtl/Chip/Processor/ALUReservationStation/ReservationStationCommon.sv"
module ALUReservationStation#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_OPCODE_INT = 3,
	parameter NUM_RESERVATION_STATION = 5,
	parameter BW_TAG = 1
)(
	input clk,
	input rst_n,

//----------From Instruction Queue----------
	`twowire_input(i_iq),
	input [BW_OPCODE_INT-1:0] i_iq_opcode,
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
	output logic [BW_OPCODE_INT-1:0] o_exe_opcode,
	output logic [BW_TAG-1:0] o_exe_tag,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_exe_V_flatten
);


logic [NUM_RESERVATION_STATION-1:0] i_iq_load_in, o_exe_selected;
logic rsv_cen;
ReservationStationCommon#(
	.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
	.NUM_OPERAND(2),
	.NUM_RESERVATION_STATION(NUM_RESERVATION_STATION),
	.BW_TAG(BW_TAG)
) u_rsv_common(
	.clk(clk),
	.rst_n(rst_n),

//----------From Instruction Queue----------
	`twowire_connect(i_iq, i_iq),
	.i_iq_Q_flatten(i_iq_Q_flatten),
	.i_iq_V_flatten(i_iq_V_flatten),
	.i_iq_tag(i_iq_tag),
	.i_iq_speculation(i_iq_speculation),

//----------From Common Data Bus----------
	`onewire_connect(i_cdb, i_cdb),
	.i_cdb_tag(i_cdb_tag),
	.i_cdb_data(i_cdb_data),

	`onewire_connect(i_branch, i_branch),
	.i_branch_correct_prediction(i_branch_correct_prediction),

//----------To Execution----------
	`twowire_connect(o_exe, o_exe),
	.o_exe_tag(o_exe_tag),
	.o_exe_V_flatten(o_exe_V_flatten),

	.i_iq_load_in(i_iq_load_in),
	.o_exe_selected(o_exe_selected),
	.rsv_cen(rsv_cen)
);
logic [BW_OPCODE_INT-1:0] o_opcode [NUM_RESERVATION_STATION], i_opcode [NUM_RESERVATION_STATION];
always @(*) begin
	for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
		i_opcode[i] = (i_iq_load_in[i]) ? i_iq_opcode : o_opcode[i];
	end
end

always@(*) begin
	o_exe_opcode = 'd0;
	for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
		o_exe_opcode = o_exe_opcode | (o_exe_selected[i] ? o_opcode[i] : 'd0);
	end
end
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
			o_opcode[i] <= 'd0;
		end
	end else if (rsv_cen) begin
		for (int i = 0; i < NUM_RESERVATION_STATION; i++) begin
			o_opcode[i] <= i_opcode[i];
		end
	end
end
endmodule
`endif