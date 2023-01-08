`ifndef __MULTIPLIER_SV__
`define __MULTIPLIER_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
module Multiplier#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_TAG = 1
)(
	input clk,
	input rst_n,

//----------From Instruction Queue----------
	
	`twowire_input(i_rsv),
	input [BW_TAG-1:0] i_rsv_tag,
	input signed [2*BW_PROCESSOR_DATA-1:0] i_rsv_V_flatten,

//----------To CDB----------
	`twowire_output(o_cdb),
	output logic [BW_TAG-1:0] o_cdb_tag,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_cdb_wdata
);

logic signed [BW_PROCESSOR_DATA-1:0] i_rsv_V[2];
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		i_rsv_V[i] = i_rsv_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA];
	end
end

logic i_cen;
Pipeline u_pl(
	.clk(clk),
	.rst(rst_n),
	.i_cen(i_cen),
	`twowire_connect(i, i_rsv),
	`twowire_connect(o, o_cdb)
);

logic signed [BW_PROCESSOR_DATA-1:0] i_cdb_wdata;
assign i_cdb_wdata = i_rsv_V[0] * i_rsv_V[1];

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_cdb_tag <= 'd0;
		o_cdb_wdata <= 'd0;
	end else if(i_cen) begin
		o_cdb_tag <= i_rsv_tag;
		o_cdb_wdata <= i_cdb_wdata;
	end
end
endmodule
`endif