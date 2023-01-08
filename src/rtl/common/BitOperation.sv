`ifndef __BIT_OPERATION_SV__
`define __BIT_OPERATION_SV__

module FindFromLsb #(parameter N = 4)(
	input [N-1:0] i_data,
	output logic [N-1:0] o_cumsum,
	output logic [N:0] o_position
);

always@(*) begin
	o_cumsum = i_data;
	for (int i = 0; i < $clog2(N); i++) begin
		o_cumsum = o_cumsum | (o_cumsum << (1<<i));
	end
	o_position = {o_cumsum, 1'b0} ^ {1'b1, o_cumsum};
end
endmodule

module Onehot2Binary #(
	parameter N = 10
)(
	input [N-1:0] i,
	output logic [$clog2(N)-1:0] o
);

always@(*) begin
	for (int j = 0; j < $clog2(N); j++) begin
		o[j] = 1'b0;
		for (int k = 0; k < N; k++) begin
			o[j] = o[j] | (((k>>j)&1) == 1) & i[k];
		end
	end
end
endmodule

module RoundRobin#(
	parameter NUM_CANDIDATE = 5
)(
	input clk,
	input rst_n,

	input [NUM_CANDIDATE-1:0] i_valid,
	output [NUM_CANDIDATE:0] o_chosen, // MSB = 1 means no one is chosen

//----------If the chosen output is taken by the next stage----------
	input i_handshake
);

localparam BW_BINARY = $clog2(NUM_CANDIDATE);

logic [2*NUM_CANDIDATE:0] result_shift_right, result;
logic [2*NUM_CANDIDATE-1:0] valid_2x, valid_shift_right_2x;
logic [BW_BINARY-1:0] selected_binary, start_binary_w, start_binary;
logic [NUM_CANDIDATE-1:0] selected_mask, selected_mask_shift_right;

FindFromLsb #(
	.N(2*NUM_CANDIDATE)
) u_ffl(
	.i_data(valid_shift_right_2x),
	.o_cumsum(),
	.o_position(result_shift_right)
);
Onehot2Binary #(
	.N(NUM_CANDIDATE)
) u_oh2b (
	.i(selected_mask),
	.o(selected_binary)
);
assign valid_2x = {2{i_valid}};
assign valid_shift_right_2x = valid_2x >> start_binary;
assign result = result_shift_right << start_binary;
assign selected_mask = (result[2*NUM_CANDIDATE-1:NUM_CANDIDATE] | result[NUM_CANDIDATE-1:0]);
assign o_chosen = {result_shift_right[2*NUM_CANDIDATE], selected_mask};

always @(*) begin
	if (start_binary == NUM_CANDIDATE - 1) begin
		start_binary_w = 'd0;
	end else begin
		start_binary_w = start_binary + 'd1;
	end
end

always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		start_binary <= 'd0;
	end else if (i_handshake) begin
		start_binary <= start_binary_w;
	end
end
endmodule

`endif
