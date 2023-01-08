`ifndef __CLOCKREPLACEMENT_SV__
`define __CLOCKREPLACEMENT_SV__

`include "../rtl/common/BitOperation.sv"
module ClockReplacement #(
	parameter ASSOCITIVITY = 2
) (
	input [ASSOCITIVITY-1:0] clock,
	input [ASSOCITIVITY-1:0] clock_use,
	output logic [ASSOCITIVITY-1:0] evicted_block_mask,
	output logic [ASSOCITIVITY-1:0] clock_use_if_evict
);

logic [ASSOCITIVITY*2-1:0] clock_extended_prefix_sum;
logic [ASSOCITIVITY*2-1:0] clock_use_extended;
logic [ASSOCITIVITY*2:0] clock_evicted_extended;
logic [ASSOCITIVITY*2:0] clock_evicted_extended_LSB;
logic [ASSOCITIVITY*2-1:0] clock_evicted_extended_cumsum;
logic [ASSOCITIVITY-1:0] clock_use_reset_region;
logic [ASSOCITIVITY*2-1:0] clock_use_reset_region_extended;

function [ASSOCITIVITY-1:0] set_from_first_one_to_MSB;
	input [ASSOCITIVITY-1:0] in;
	logic [ASSOCITIVITY-1:0] out;
	out = in;
	begin
		for(int i = 1; i < ASSOCITIVITY*2; i = 2*i) begin
			out = (out | (out << i));
		end
		set_from_first_one_to_MSB = out;
	end
endfunction

FindFromLsb #(.N(2*ASSOCITIVITY)) u_invalid_block_selector(
	.i_data(clock_evicted_extended[2*ASSOCITIVITY:1]),
	.o_cumsum(clock_evicted_extended_cumsum),
	.o_position(clock_evicted_extended_LSB)
);

always@(*) begin
	clock_extended_prefix_sum = {{(ASSOCITIVITY){1'b1}}, set_from_first_one_to_MSB(clock)};
	clock_use_extended = {(clock_use & (~clock)),clock_use}; // set the use bit of clock in the second comparison 0, make sure the clock is chosen if everyone's use bit is 1
	clock_evicted_extended = 'd0;
	for (int i = 0; i < 2*ASSOCITIVITY; i++) begin
		clock_evicted_extended[i+1] = (clock_evicted_extended[i] || (!clock_use_extended[i])) && clock_extended_prefix_sum[i];
	end
	evicted_block_mask = clock_evicted_extended_LSB[2*ASSOCITIVITY-1:ASSOCITIVITY] | clock_evicted_extended_LSB[ASSOCITIVITY-1:0];

	clock_use_reset_region_extended = clock_evicted_extended_cumsum ^ clock_extended_prefix_sum;
	clock_use_reset_region = clock_use_reset_region_extended[2*ASSOCITIVITY-1:ASSOCITIVITY] | clock_use_reset_region_extended[ASSOCITIVITY-1:0];
	clock_use_if_evict = clock_use & (~clock_use_reset_region);

end

endmodule
`endif
