`ifndef __CONTROLLER_SV__
`define __CONTROLLER_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/BitOperation.sv"

module Pipeline(
	input clk,
	input rst,
	`twowire_input(i),
	output logic i_cen,
	`twowire_output(o)
);
logic o_valid_w;
assign o_valid_w = i_valid || (o_valid && !o_ready);
assign i_ready = !o_valid || o_ready;
assign i_cen = i_ready && i_valid;

always@(posedge clk or negedge rst) begin
	if(!rst) begin o_valid <= 1'b0     ; end
	else     begin o_valid <= o_valid_w; end
end
endmodule

module PipelineWhisper #(
	parameter DIM = 9
)(
	input [DIM-1:0] i_target,

	`twowire_input(i),
	`twowires_output(o, DIM)
);
logic [DIM-1:0] wanted_and_valid;
assign i_ready = |wanted_and_valid;
always@(*) begin
	for (int i = 0; i < DIM; i++) begin
		wanted_and_valid[i] = i_target[i] && o_ready[i];
	end
end
always@(*) begin
	for(int i = 0; i < DIM; i++) begin
		o_valid[i] = i_valid && i_target[i];
	end
end

endmodule

module PipelineRadio #(
	parameter DIM = 7
)(
	input [DIM-1:0] i_mask,	
	`twowires_input(i, DIM),
	`twowire_output(o)
);
logic [DIM-1:0] valid_and_wanted;
always@(*) begin
	for(int i = 0; i < DIM; i++) begin
		valid_and_wanted[i] = (i_valid[i] && i_mask[i]);
	end
	o_valid = |valid_and_wanted;
	
	for(int i = 0; i < DIM; i++) begin
		i_ready[i] = o_ready && i_mask[i];
	end
end

endmodule

module AddressQueueSpeculationController #( // can take NUM_FIFO_INPUT_ENTRY inputs at one time, but only output one output at one time
	parameter N = 4
)(
	input clk,
	input rst_n,

	`twowire_input(i),
	`twowire_output(o),
	`onewire_input(i_branch),
	input i_branch_correct_prediction,
	input i_iq_speculation,
	output logic [N-1:0] o_load_in,
	output logic [N-2:0] o_forward
);
logic i_cen, o_cen;
logic [N  :0] vacancy;
logic [N-1:0] valid, valid_w, valid_before_flush;
logic o_speculation, i_speculation;
logic [N-1:0] i_unspeculative_region, o_unspeculative_region;
logic i_flush;

assign o_valid = valid[0];
assign i_cen   = i_valid && i_ready;
assign o_cen   = o_valid && o_ready;
always@(*) begin
	i_flush = i_branch_valid && !i_branch_correct_prediction;
	if (i_flush) begin
		valid = valid_before_flush & o_unspeculative_region;
	end else begin
		valid = valid_before_flush;
	end
	i_ready = !valid[N-1] && !i_flush;// || o_ready;
	vacancy = {1'b1, ~valid} & {valid, 1'b1};

	case({o_cen, i_cen})
		2'b11: begin
			o_load_in = vacancy[N:1];
			o_forward = valid[N-1:1];
			valid_w   = valid;
		end
		2'b10: begin
			o_load_in = 'd0;
			o_forward = valid[N-1:1];
			valid_w   = valid >> 1;
		end
		2'b01: begin
			o_load_in = vacancy[N-1:0];
			o_forward = 'd0;
			valid_w   = {valid[N-2:0], 1'b1};
		end
		2'b00: begin
			o_load_in = 'd0;
			o_forward = 'd0;
			valid_w   = valid;
		end
	endcase
	if (i_branch_valid) begin
		i_speculation = 1'b0;
	end else begin
		i_speculation = i_iq_speculation;
	end
	if (!o_speculation && i_iq_speculation) begin
		i_unspeculative_region = valid;
	end else if (o_cen) begin
		i_unspeculative_region = o_unspeculative_region >> 1;
	end else begin
		i_unspeculative_region = o_unspeculative_region;
	end
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		valid_before_flush <= 'd0;
	end else if(o_cen || i_cen || i_flush) begin
		valid_before_flush <= valid_w;
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_speculation <= 1'b0;
	end else begin
		o_speculation <= i_speculation;
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_unspeculative_region <= 'd0;
	end else if((!o_speculation && i_iq_speculation) || o_cen) begin
		o_unspeculative_region <= i_unspeculative_region;
	end
end

endmodule

module MultiInputFifoController #( // can take NUM_FIFO_INPUT_ENTRY inputs at one time, but only output one output at one time
	parameter N = 4,
	parameter NUM_FIFO_INPUT_ENTRY = 1, // The number of input the FIFO can take at one time
	parameter BW_PC_MOD = 4
)(
	input clk,
	input rst_n,

	`twowire_input(i),
	`twowire_output(o),
	input i_flush,
	input [BW_PC_MOD-1:0] i_pc_mod_select,
	input [BW_PC_MOD-1:0] i_pc_upperbound,
	output logic [$clog2(N)-1:0] write_ptr,
	output logic [N-2:0] o_forward
);
logic i_cen, o_cen;
logic [$clog2(N)-1:0] tail_w, tail_before_flush;
logic [N-1:0] forward;
logic [$clog2(N)-1:0] tail;

assign i_cen   = i_valid && i_ready;
assign o_cen   = o_valid && o_ready;
always@(*) begin
	if (i_flush) begin
		tail = 'd0;
	end else begin
		tail = tail_before_flush;
	end
	o_valid = tail > 'd0;
	i_ready = (tail <= (N - NUM_FIFO_INPUT_ENTRY)) && !i_flush;
	for (int i = 0; i < N; i++) begin
		forward[i] = (i+1) < tail;
	end

	case({o_cen, i_cen})
		2'b11: begin
			tail_w = tail + (i_pc_upperbound - i_pc_mod_select);
			o_forward = forward;
			write_ptr = tail - 'd1;
		end
		2'b10: begin
			tail_w = tail - 'd1;
			o_forward = forward;
			write_ptr = tail - 'd1;
		end
		2'b01: begin
			tail_w = tail + (i_pc_upperbound - i_pc_mod_select) + 'd1;
			o_forward = 'd0;
			write_ptr = tail;
		end
		2'b00: begin
			tail_w = tail;
			o_forward = 'd0;
			write_ptr = tail;
		end
	endcase
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		tail_before_flush <= 'd0;
	end else if(o_cen || i_cen || i_flush) begin
		tail_before_flush <= tail_w;
	end
end

endmodule
`endif
