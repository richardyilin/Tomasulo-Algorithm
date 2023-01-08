`ifndef __REGISTERFILE_SV__
`define __REGISTERFILE_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
module RegisterFile#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter BW_TAG = 1
)(
	input clk,
	input rst_n,

//----------From/To Instruction Queue----------
	`onewire_input(i_iq),
	// rs
	input [9:0] i_iq_rs_flatten,
	output logic [2*BW_TAG-1:0] o_iq_Q_flatten,
	output logic signed [2*BW_PROCESSOR_DATA-1:0] o_iq_V_flatten,
	//rd
	input [4:0] i_iq_rd,
	input [BW_TAG-1:0] i_iq_tag,

	input i_iq_speculation,

//----------Speculation----------
	`onewire_input(i_branch),
	input i_branch_correct_prediction,

//----------From CDB to future file----------
	`onewire_input(i_cdb),
	input [BW_TAG-1:0] i_cdb_tag,
	input signed [BW_PROCESSOR_DATA-1:0] i_cdb_wdata
);

logic [BW_TAG-1:0] register_status_table[31], register_status_table_w[2][31];
logic signed [BW_PROCESSOR_DATA-1:0] register_file[31], register_file_w[2][31];
logic [BW_TAG-1:0] history_register_status_table[31], history_register_status_table_w[31];
logic signed [BW_PROCESSOR_DATA-1:0] history_register_file[31], history_register_file_w[31];
logic [4:0] rs[2], rd;
logic [4:0] i_iq_rs[2];
logic [BW_TAG-1:0] o_iq_Q[2];
logic signed [BW_PROCESSOR_DATA-1:0] o_iq_V[2];
logic flush;
logic correct_prediction;
assign flush = i_branch_valid && !i_branch_correct_prediction;
assign correct_prediction = i_branch_valid && i_branch_correct_prediction;
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		i_iq_rs[i] = i_iq_rs_flatten[i*5 +: 5];
		o_iq_Q_flatten[i*BW_TAG +: BW_TAG] = o_iq_Q[i];
		o_iq_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA] = o_iq_V[i];
	end
end
always@(*) begin
	for (int i = 0; i < 2; i++) begin
		rs[i] = i_iq_rs[i] - 'd1;
		if (i_iq_rs[i] == 'd0) begin // read x0
			o_iq_Q[i] = 'd0;
			o_iq_V[i] = 'd0;
		end else begin
			o_iq_Q[i] = register_status_table[rs[i]];
			o_iq_V[i] = register_file[rs[i]];
		end
	end
end
always@(*) begin
	for (int i = 0; i < 31; i++) begin
		if (flush) begin
			register_status_table_w[0][i] = history_register_status_table[i];
			register_file_w[0][i] = history_register_file[i];
		end else begin
			register_status_table_w[0][i] = register_status_table[i];
			register_file_w[0][i] = register_file[i];
		end
	end
	for (int i = 0; i < 31; i++) begin
		if (i_cdb_valid && register_status_table_w[0][i] == i_cdb_tag) begin // CDB writes value into register file
			register_status_table_w[1][i] = 'd0;
			register_file_w[1][i] = i_cdb_wdata;
		end else begin
			register_status_table_w[1][i] = register_status_table_w[0][i];
			register_file_w[1][i] = register_file_w[0][i];
		end
	end
	rd = i_iq_rd - 'd1;
	if (i_iq_valid && i_iq_rd != 'd0 && !flush) begin // write the tag of the rd of the instruction which write to rd to RST
		register_status_table_w[1][rd] = i_iq_tag;
	end
	
	for (int i = 0; i < 31; i++) begin
		history_register_file_w[i] = history_register_file[i];
		history_register_status_table_w[i] = history_register_status_table[i];
		if (correct_prediction) begin
			history_register_file_w[i] = register_file_w[1][i]; // cannot be register_file because o_speculation is still 1 at this cycle (it will be 0 in the next cycle), we cannot write i_iq_tag in history buffer if we use register_file instead of register_file_w[1]
			history_register_status_table_w[i] = register_status_table_w[1][i];
		end
		if (i_cdb_valid && history_register_status_table_w[i] == i_cdb_tag) begin // CDB writes value into register file
			history_register_status_table_w[i] = 'd0;
			history_register_file_w[i] = i_cdb_wdata;
		end
	end
	if (i_iq_valid && i_iq_rd != 'd0 && !i_iq_speculation) begin // write the tag of the rd of the instruction which write to rd to RST
		history_register_status_table_w[rd] = i_iq_tag;
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < 31; i++) begin
			register_status_table[i] <= 'd0;
		end
	end else if (i_iq_valid || i_cdb_valid || flush) begin
		for (int i = 0; i < 31; i++) begin
			register_status_table[i] <= register_status_table_w[1][i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < 31; i++) begin
			register_file[i] <= 'd0;
		end
	end else if (i_cdb_valid || flush) begin
		for (int i = 0; i < 31; i++) begin
			register_file[i] <= register_file_w[1][i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < 31; i++) begin
			history_register_status_table[i] <= 'd0;
		end
	end else if (i_iq_valid || i_cdb_valid || i_branch_valid) begin
		for (int i = 0; i < 31; i++) begin
			history_register_status_table[i] <= history_register_status_table_w[i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < 31; i++) begin
			history_register_file[i] <= 'd0;
		end
	end else if (i_cdb_valid || i_branch_valid) begin
		for (int i = 0; i < 31; i++) begin
			history_register_file[i] <= history_register_file_w[i];
		end
	end
end

endmodule
`endif