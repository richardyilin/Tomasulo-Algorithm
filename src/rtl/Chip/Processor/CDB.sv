`ifndef __CDB_SV__
`define __CDB_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
`include "../rtl/common/BitOperation.sv"
module CDB#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_TAG = 1,
	parameter NUM_KINDS_OF_RESERVATION_STATION = 5,
	parameter NUM_KINDS_OF_UNIT = 4,
	parameter BW_ADDRESS = 32
)(
	input clk,
	input rst_n,


//----------From Integer Unit----------
	`twowire_input (i_int),
	input [BW_TAG-1:0] i_int_tag,
	input signed [BW_PROCESSOR_DATA-1:0] i_int_wdata,

//----------From Multiplier----------
	`twowire_input (i_mul),
	input [BW_TAG-1:0] i_mul_tag,
	input signed [BW_PROCESSOR_DATA-1:0] i_mul_wdata,

//----------From Branch Unit----------
	`twowire_input (i_branch),
	input [BW_TAG-1:0] i_branch_tag,
	input [BW_ADDRESS-1:0] i_branch_wdata, // jal, jalr needs to store PC+4 in rd

//----------From Load Store Unit load data----------
	`twowire_input (i_load),
	input [BW_TAG-1:0] i_load_tag,
	input [BW_PROCESSOR_DATA-1:0] i_load_wdata,

//----------To Register File----------
	`onewire_output(o_rf),
	output logic [BW_TAG-1:0] o_rf_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_rf_data,

//----------To Integer Unit----------
	`onewire_output(o_int),
	output logic [BW_TAG-1:0] o_int_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_int_data,

//----------To Multiplier----------
	`onewire_output(o_mul),
	output logic [BW_TAG-1:0] o_mul_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_mul_data,

//----------To Load Store----------
	`onewire_output(o_lsu),
	output logic [BW_TAG-1:0] o_lsu_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_lsu_data,

//----------To branch----------
	`onewire_output(o_branch),
	output logic [BW_TAG-1:0] o_branch_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_branch_data
);

localparam NUM_INPUT = NUM_KINDS_OF_UNIT;
localparam NUM_DATA_SET = NUM_KINDS_OF_UNIT;
logic [BW_TAG-1:0] o_tag;
logic [BW_PROCESSOR_DATA-1:0] o_data;
logic [BW_TAG-1:0] o_tag_set[NUM_INPUT];
logic [BW_PROCESSOR_DATA-1:0] o_data_set[NUM_DATA_SET];
logic [NUM_INPUT-1:0] o_selected;
logic [NUM_INPUT:0] o_selected_extended;
`twowires_logic(i_radio, NUM_INPUT);
`twowire_logic(o_radio);
assign i_radio_valid[`INT] = i_int_valid;
assign i_int_ready = i_radio_ready[`INT];
assign i_radio_valid[`MUL] = i_mul_valid;
assign i_mul_ready = i_radio_ready[`MUL];
assign i_radio_valid[`BRANCH] = i_branch_valid;
assign i_branch_ready = i_radio_ready[`BRANCH];
assign i_radio_valid[`LOAD_STORE] = i_load_valid;
assign i_load_ready = i_radio_ready[`LOAD_STORE];
assign o_selected = o_selected_extended[NUM_INPUT-1:0];

FindFromLsb #(.N(NUM_INPUT)) u_ffl(
	.i_data(i_radio_valid),
	.o_cumsum(),
	.o_position(o_selected_extended)
);
PipelineRadio #(
	.DIM(NUM_INPUT)
) u_radio(
	.i_mask(o_selected),
	`twowire_connect(i, i_radio),
	`twowire_connect(o, o_radio)
);
assign o_radio_ready = 1'b1;


assign o_rf_tag = o_tag;
assign o_rf_data = o_data;
assign o_int_tag = o_tag;
assign o_int_data = o_data;
assign o_mul_tag = o_tag;
assign o_mul_data = o_data;
assign o_branch_tag = o_tag;
assign o_branch_data = o_data;
assign o_lsu_tag = o_tag;
assign o_lsu_data = o_data;

assign o_rf_valid = o_radio_valid;
assign o_int_valid = o_radio_valid;
assign o_mul_valid = o_radio_valid;
assign o_branch_valid = o_radio_valid;
assign o_lsu_valid = o_radio_valid;

always@(*) begin
	o_tag_set[`INT] = i_int_tag;
	o_tag_set[`MUL] = i_mul_tag;
	o_tag_set[`BRANCH] = i_branch_tag;
	o_tag_set[`LOAD_STORE] = i_load_tag;
	o_tag = 'd0;
	for (int i = 0; i < NUM_INPUT; i++) begin
		o_tag = o_tag | ((o_selected[i]) ? o_tag_set[i] : 'd0);
	end
	o_data_set[`INT] = i_int_wdata;
	o_data_set[`MUL] = i_mul_wdata;
	o_data_set[`BRANCH] = i_branch_wdata;
	o_data_set[`LOAD_STORE] = i_load_wdata;
	o_data = 'd0;
	for (int i = 0; i < NUM_DATA_SET; i++) begin
		o_data = o_data | ((o_selected[i]) ? o_data_set[i] : 'd0);
	end
end
endmodule
`endif