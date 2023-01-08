`ifndef __INTEGERUNIT_SV__
`define __INTEGERUNIT_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
module IntegerUnit#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_OPCODE_INT = 3,
	parameter BW_TAG = 1
)(
	input clk,
	input rst_n,

//----------From Reservation Station----------
	
	`twowire_input(i_rsv),
	input [BW_OPCODE_INT-1:0] i_rsv_opcode,
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

logic [4:0] i_shamt;
logic signed [BW_PROCESSOR_DATA-1:0] i_cdb_wdata;
logic [BW_PROCESSOR_DATA-1:0] u_i_rsv_V1, u_i_rsv_V2;
assign i_shamt = i_rsv_V[1][4:0];
assign u_i_rsv_V1 = i_rsv_V[0];
assign u_i_rsv_V2 = i_rsv_V[1];
always @(*) begin
	i_cdb_wdata = i_rsv_V[0] + i_rsv_V[1];
	case (i_rsv_opcode)
		`ADD: begin
			i_cdb_wdata = i_rsv_V[0] + i_rsv_V[1];
		end
		`MINUS: begin
			i_cdb_wdata = i_rsv_V[0] - i_rsv_V[1];
		end
		`SLT: begin
			i_cdb_wdata = (i_rsv_V[0] < i_rsv_V[1]) ? 'd1 : 'd0;
		end
		`XOR: begin
			i_cdb_wdata = i_rsv_V[0] ^ i_rsv_V[1];
		end
		`OR: begin
			i_cdb_wdata = i_rsv_V[0] | i_rsv_V[1];
		end
		`AND: begin
			i_cdb_wdata = i_rsv_V[0] & i_rsv_V[1];
		end
		`SLLI: begin
			i_cdb_wdata = i_rsv_V[0] << i_shamt;
		end
		`SRAI: begin
			i_cdb_wdata = i_rsv_V[0] >>> i_shamt;
		end
		`SRLI: begin
			i_cdb_wdata = i_rsv_V[0] >> i_shamt;
		end
		`AUIPC: begin
			i_cdb_wdata = u_i_rsv_V1 + u_i_rsv_V2;
		end
		default: ;
	endcase
end

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