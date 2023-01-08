`ifndef __CACHE_SV__
`define __CACHE_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/Chip/Processor/PC/CorrelatingBranchPredictor.sv"
`include "../rtl/Chip/Cache/ClockReplacement.sv"
module Cache #(
	parameter BW_ADDRESS = 32,
	parameter LATENCY = 4,
	parameter ASSOCITIVITY = 2,
	parameter NUM_SET = 256,
	parameter BW_LAST_BLOCK = 32,
	parameter BW_BLOCK = 128
)(
	// Interface for the last level (data requester or writer)
	input clk,
	input rst_n,
	input i_valid,
	input i_r0w1, // r = 0, w = 1
	input [BW_ADDRESS-1:0] i_rwaddr,
	input        [BW_LAST_BLOCK-1:0] i_wdata,
	output logic i_ready,
	output logic [BW_LAST_BLOCK-1:0] i_rdata,

	// interface for the next level

	input o_ready,
	input [BW_BLOCK-1:0] o_rdata,
	output logic o_valid,
	output logic o_r0w1, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] o_rwaddr,
	output logic [BW_BLOCK-1:0] o_wdata
);

localparam INIT = 0;
localparam WRITE_BACK_READ = 1;
localparam WRTIE_BACK_WRTIE = 2;
localparam WRITE_AGAIN = 3;
localparam READ_NEXT_LEVEL = 4;
localparam READ_READY = 5;
`ifndef SYNTHESIS
	localparam BUBBLE = 6;
`endif

localparam NUM_LAST_BLOCK_PER_CURRENT_BLOCK = BW_BLOCK / BW_LAST_BLOCK;
localparam BW_INDEX = $clog2(NUM_SET);
localparam BW_OFFSET =  $clog2(BW_BLOCK / BW_LAST_BLOCK);
localparam BW_TAG = BW_ADDRESS - BW_INDEX - ($clog2(BW_BLOCK) - `BW_BYTE);

logic [BW_LAST_BLOCK-1:0] i_rdata_w;
logic o_valid_w;
logic o_r0w1_w; // r = 0, w = 1
logic [BW_ADDRESS-1:0] o_rwaddr_w;
logic [BW_BLOCK-1:0] o_wdata_w;

logic [3:0] state, state_w;
`ifndef SYNTHESIS
	logic [$clog2(LATENCY+1)-1:0] count, count_w;
`endif
logic [BW_INDEX-1+(BW_INDEX<=0):0] i_index, s1_index;
logic [BW_OFFSET-1+(BW_OFFSET<=0):0] i_offset, s1_offset;
logic [ASSOCITIVITY-1:0] i_read_hit_block_mask, i_write_hit_block_mask;
logic [ASSOCITIVITY-1:0] i_written_block_mask_when_miss, s1_written_block_mask_when_miss;
logic [ASSOCITIVITY-1:0] i_invalid_block_mask;
logic [ASSOCITIVITY:0] i_chosen_invalid_block_mask;
logic [ASSOCITIVITY-1:0] i_evicted_block_mask;
logic [BW_LAST_BLOCK-1:0] i_hit_data;
logic i_cache_full;
logic i_must_write_back;

logic [ASSOCITIVITY-1:0] dirty [NUM_SET], dirty_w [NUM_SET];
logic [ASSOCITIVITY-1:0] valid [NUM_SET][NUM_LAST_BLOCK_PER_CURRENT_BLOCK], valid_w [NUM_SET][NUM_LAST_BLOCK_PER_CURRENT_BLOCK];
logic [BW_TAG-1:0] tags [NUM_SET][ASSOCITIVITY], tags_w [NUM_SET][ASSOCITIVITY];
logic [BW_LAST_BLOCK-1:0] data [NUM_SET][ASSOCITIVITY][NUM_LAST_BLOCK_PER_CURRENT_BLOCK], data_w [NUM_SET][ASSOCITIVITY][NUM_LAST_BLOCK_PER_CURRENT_BLOCK];

logic [BW_TAG-1:0] i_evicted_tag;
logic i_write_hit, i_read_hit;
logic [NUM_LAST_BLOCK_PER_CURRENT_BLOCK-1:0] i_offset_mask, s1_offset_mask;
logic i_read_to_replace_invalid;

logic [BW_TAG-1:0] s1_evicted_tag;
logic [BW_TAG-1:0] i_tag, s1_tag;
logic [ASSOCITIVITY-1:0] s1_evicted_block_mask;
logic s1_r0w1;
logic [BW_ADDRESS-1:0] s1_rwaddr;
logic [BW_LAST_BLOCK-1:0] s1_wdata;

assign i_tag = i_rwaddr[BW_ADDRESS-1:BW_ADDRESS-BW_TAG];
assign i_must_write_back = |(i_evicted_block_mask & dirty[i_index]);


FindFromLsb #(.N(ASSOCITIVITY)) u_invalid_block_selector(
	.i_data(i_invalid_block_mask),
	.o_cumsum(),
	.o_position(i_chosen_invalid_block_mask)
);

logic [ASSOCITIVITY-1:0] clock_use [NUM_SET], clock_use_w [NUM_SET], clock_use_if_evict;
logic [ASSOCITIVITY-1:0] clock[NUM_SET], clock_w[NUM_SET];

ClockReplacement #(
	.ASSOCITIVITY(ASSOCITIVITY)
) u_clock (
	.clock(clock[i_index]),
	.clock_use(clock_use[i_index]),
	.evicted_block_mask(i_evicted_block_mask),
	.clock_use_if_evict(clock_use_if_evict)
);

always@(*) begin
	// handle when there is no i_index bits or no i_offset bits
	if (BW_INDEX == 0) begin
		i_index = 'd0;
	end else begin
		i_index = i_rwaddr[BW_ADDRESS-BW_TAG-1+(BW_INDEX<=0):BW_ADDRESS-BW_TAG-BW_INDEX];
	end
	if (BW_OFFSET == 0) begin
		i_offset = 'd0;
	end else begin
		i_offset = i_rwaddr[BW_ADDRESS-BW_TAG-BW_INDEX-1+(BW_OFFSET<=0):BW_ADDRESS-BW_TAG-BW_INDEX-BW_OFFSET];
	end
	`ifndef SYNTHESIS
		count_w = count;
	`endif
	state_w = state;
	i_ready = 1'b0;
	o_valid_w = 1'b0;
	o_r0w1_w = o_r0w1; // r = 0, w = 1
	o_rwaddr_w = o_rwaddr;
	o_wdata_w = o_wdata;;
	for (int i = 0; i < NUM_SET; i++) begin
		dirty_w[i] = dirty[i];
		for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
			valid_w[i][j] = valid[i][j];
		end
	end
	for (int i = 0; i < NUM_SET; i++) begin
		for (int j = 0; j < ASSOCITIVITY; j++) begin
			tags_w[i][j] = tags[i][j];
			for (int k = 0; k < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; k++) begin
				data_w[i][j][k] = data[i][j][k];
			end
		end
	end

	for (int i = 0; i < NUM_SET; i++) begin
		clock_w[i] = clock[i];
		clock_use_w[i] = clock_use[i];
	end
	i_offset_mask = 'd1 << i_offset;
	s1_offset_mask = 'd1 << s1_offset;
	i_hit_data = 'd0;
	for (int i = 0; i < ASSOCITIVITY; i++) begin
		i_read_hit_block_mask[i] = valid[i_index][i_offset][i] && (i_tag == tags[i_index][i]);
		i_hit_data = i_hit_data | (i_read_hit_block_mask[i] ? data[i_index][i][i_offset] : 'd0);
		i_write_hit_block_mask[i] = (i_tag == tags[i_index][i]);
		i_invalid_block_mask[i] = 1'b1;
		for (int k = 0; k < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; k++) begin
			i_invalid_block_mask[i] = i_invalid_block_mask[i] && (!valid[i_index][k][i]); // any subset of block is valid makes entire block valid
		end
	end
	i_read_hit = |i_read_hit_block_mask;
	i_write_hit = |i_write_hit_block_mask;

	i_cache_full = i_chosen_invalid_block_mask[ASSOCITIVITY];
	if (i_cache_full) begin
		i_written_block_mask_when_miss = i_evicted_block_mask;
	end else begin 
		i_written_block_mask_when_miss = i_chosen_invalid_block_mask[ASSOCITIVITY-1:0];
	end
	i_rdata_w = i_hit_data;
	i_evicted_tag = 'd0;
	for (int i = 0; i < ASSOCITIVITY; i++) begin
		i_evicted_tag = i_evicted_tag | (i_evicted_block_mask[i] ? tags[i_index][i] : 'd0);
	end
	i_read_to_replace_invalid = 1'b0; // there is an invalid subset of block in the block we are going to write back, so we need to read from lower level to replace them with correct data first
	for (int i = 0; i < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; i++) begin
		for (int j = 0; j < ASSOCITIVITY; j++) begin
			i_read_to_replace_invalid = i_read_to_replace_invalid | (!valid[i_index][i][j] && (i_evicted_block_mask[j]));
		end
	end
	case (state)
		INIT: begin
			`ifndef SYNTHESIS
				count_w = 'd0;
			`endif
			i_ready = i_r0w1 && i_valid;
			if (i_r0w1) begin
				if (i_write_hit) begin // write hit
					`ifndef SYNTHESIS
						if (i_valid) begin
							if (LATENCY >= 1) begin
								state_w = BUBBLE;
							end else begin
								state_w = INIT;
							end
						end
					`else
						if (i_valid) begin
							state_w = INIT;
						end
					`endif
					for (int i = 0; i < ASSOCITIVITY; i++) begin
						if (i_write_hit_block_mask[i]) begin
							data_w[i_index][i][i_offset] = i_wdata;
						end
						valid_w[i_index][i_offset] = valid[i_index][i_offset] | i_write_hit_block_mask;
						dirty_w[i_index] = dirty[i_index] | i_write_hit_block_mask;
						clock_use_w[i_index] = clock_use[i_index] | i_write_hit_block_mask;
					end
				end else begin // write miss
					if (i_cache_full && i_must_write_back) begin // write miss and all block is full, evict one block (write to next level)
						if (i_valid) begin
							if (i_read_to_replace_invalid) begin
								state_w = WRITE_BACK_READ;
							end else begin
								state_w = WRTIE_BACK_WRTIE;
							end
							o_valid_w = 1'b1;
						end
						if (i_read_to_replace_invalid) begin
							o_r0w1_w = 1'b0;
							o_rwaddr_w = {i_evicted_tag, i_rwaddr[BW_ADDRESS-1-BW_TAG:0]};
						end else begin
							o_r0w1_w = 1'b1;
							o_rwaddr_w = {i_evicted_tag, i_rwaddr[BW_ADDRESS-1-BW_TAG:0]};
							o_wdata_w = 'd0;
							for (int i = 0; i < ASSOCITIVITY; i++) begin  // concatenation
								for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
									o_wdata_w[j*BW_LAST_BLOCK+:BW_LAST_BLOCK] = o_wdata_w[j*BW_LAST_BLOCK+:BW_LAST_BLOCK] | (i_evicted_block_mask[i] ? data[i_index][i][j] : 'd0);
								end
							end
						end
						clock_w[i_index] = i_evicted_block_mask;
					end else begin // write miss but there is an invalid block, or the evicted block is not dirty, write to that block						
						`ifndef SYNTHESIS
							if (i_valid) begin
								if (LATENCY >= 1) begin
									state_w = BUBBLE;
								end else begin
									state_w = INIT;
								end
							end
						`else
							if (i_valid) begin
								state_w = INIT;
							end
						`endif
						for (int i = 0; i < ASSOCITIVITY; i++) begin
							if (i_written_block_mask_when_miss[i]) begin // cannot use i_chosen_invalid_block_mask because it may be evicted block but it happens to be clean
								tags_w[i_index][i] = i_tag;
								data_w[i_index][i][i_offset] = i_wdata;
								for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
									valid_w[i_index][j][i] = i_offset_mask[j]; // When we write to a block that does not need to update, set rest of the valid bits 0
								end
							end
						end
						dirty_w[i_index] = dirty[i_index] | i_written_block_mask_when_miss;
						clock_use_w[i_index] = clock_use[i_index] | i_written_block_mask_when_miss;
					end
				end
			end else begin
				if (i_read_hit) begin // read hit
					`ifndef SYNTHESIS
						if (i_valid) begin
							if (LATENCY > 1) begin
								state_w = BUBBLE;
							end else begin
								state_w = READ_READY;
							end
						end
					`else
						if (i_valid) begin
							state_w = READ_READY;
						end
					`endif
					clock_use_w[i_index] = clock_use[i_index] | i_read_hit_block_mask;
				end else begin // read miss
					if (i_valid) begin
						o_valid_w = 1'b1;
					end
					if (i_cache_full && i_must_write_back) begin // evict one block
						if (i_valid) begin
							if (i_read_to_replace_invalid) begin
								state_w = WRITE_BACK_READ;
							end else begin
								state_w = WRTIE_BACK_WRTIE;
							end
						end
						if (i_read_to_replace_invalid) begin
							o_r0w1_w = 1'b0;
							o_rwaddr_w = {i_evicted_tag, i_rwaddr[BW_ADDRESS-1-BW_TAG:0]};
						end else begin
							o_r0w1_w = 1'b1;
							o_rwaddr_w = {i_evicted_tag, i_rwaddr[BW_ADDRESS-1-BW_TAG:0]};
							o_wdata_w = 'd0;
							for (int i = 0; i < ASSOCITIVITY; i++) begin  // concatenation
								for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
									o_wdata_w[j*BW_LAST_BLOCK+:BW_LAST_BLOCK] = o_wdata_w[j*BW_LAST_BLOCK+:BW_LAST_BLOCK] | (i_evicted_block_mask[i] ? data[i_index][i][j] : 'd0);
								end
							end
						end
						clock_w[i_index] = i_evicted_block_mask;
					end else begin // read data from next level
						if (i_valid) begin
							state_w = READ_NEXT_LEVEL;
						end
						o_r0w1_w = 1'b0;
						o_rwaddr_w = i_rwaddr;
						clock_use_w[i_index] = clock_use[i_index] | i_read_hit_block_mask;
					end
				end
			end
		end
		WRITE_BACK_READ: begin 
			o_valid_w = 1'b1;
			if (o_ready) begin
				state_w = WRTIE_BACK_WRTIE;
				o_r0w1_w = 1'b1;
				for (int i = 0; i < ASSOCITIVITY; i++) begin
					if (s1_evicted_block_mask[i]) begin
						for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
							if (!valid[s1_index][j][i]) begin // we do not need to change the valid data in the cache, just write to the invalid subset of block
								data_w[s1_index][i][j] = o_rdata[j*BW_LAST_BLOCK+:BW_LAST_BLOCK];
							end
						end
					end
				end
				o_rwaddr_w = {s1_evicted_tag, s1_rwaddr[BW_ADDRESS-1-BW_TAG:0]};
				o_wdata_w = 'd0;
				for (int i = 0; i < ASSOCITIVITY; i++) begin  // concatenation
					for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
						o_wdata_w[j*BW_LAST_BLOCK+:BW_LAST_BLOCK] = o_wdata_w[j*BW_LAST_BLOCK+:BW_LAST_BLOCK] | (s1_evicted_block_mask[i] ? data_w[s1_index][i][j] : 'd0);
					end
				end
			end
		end
		WRTIE_BACK_WRTIE: begin
			o_valid_w = 1'b1;
			if (o_ready) begin
				if (s1_r0w1) begin
					o_valid_w = 1'b0;
					`ifndef SYNTHESIS
						if (LATENCY >= 1) begin
							state_w = BUBBLE;
						end else begin
							state_w = INIT;
						end
					`else
						state_w = INIT;
					`endif

					for (int i = 0; i < ASSOCITIVITY; i++) begin
						if (s1_evicted_block_mask[i]) begin // cannot use chosen_invalid_block_mask because it may be evicted block but it happens to be clean
							tags_w[s1_index][i] = s1_tag;
							data_w[s1_index][i][s1_offset] = s1_wdata;
							for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
								valid_w[s1_index][j][i] = s1_offset_mask[j]; // When we write to a block that does not need to update, set rest of the valid bits 0
							end
						end
					end
					dirty_w[s1_index] = dirty[s1_index] | s1_evicted_block_mask;
					clock_use_w[s1_index] = clock_use[s1_index] | s1_evicted_block_mask;
				end else begin
					state_w = READ_NEXT_LEVEL;
					o_r0w1_w = 1'b0;
					o_rwaddr_w = {s1_tag, s1_rwaddr[BW_ADDRESS-1-BW_TAG:0]};
				end
			end
		end
		READ_NEXT_LEVEL: begin
			o_valid_w = !o_ready;
			if (o_ready) begin
				`ifndef SYNTHESIS
					if (LATENCY > 1) begin
						state_w = BUBBLE;
					end else begin
						state_w = READ_READY;
					end
				`else
					state_w = READ_READY;
				`endif
				for (int i = 0; i < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; i++) begin
					for (int j = 0; j < ASSOCITIVITY; j++) begin
						valid_w[s1_index][i][j] = valid[s1_index][i][j] || s1_written_block_mask_when_miss[j];
					end
				end
				for (int j = 0; j < ASSOCITIVITY; j++) begin
					dirty_w[s1_index][j] = dirty[s1_index][j] && (!s1_written_block_mask_when_miss[j]);
				end
				for (int i = 0; i < ASSOCITIVITY; i++) begin
					if (s1_written_block_mask_when_miss[i]) begin
						tags_w[s1_index][i] = s1_tag;
						for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
							data_w[s1_index][i][j] = o_rdata[j*BW_LAST_BLOCK+:BW_LAST_BLOCK];
						end
					end
				end
				i_rdata_w = 'd0;
				for (int i = 0; i < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; i++) begin
					i_rdata_w = i_rdata_w | (s1_offset_mask[i] ? o_rdata[i*BW_LAST_BLOCK+:BW_LAST_BLOCK] : 'd0);
				end
				clock_use_w[s1_index] = clock_use[s1_index] | s1_written_block_mask_when_miss;
			end
		end
		READ_READY: begin
			state_w = INIT;
			i_ready = 1'b1;
		end
		`ifndef SYNTHESIS
			BUBBLE: begin
				count_w = count + 'd1;
				if (s1_r0w1) begin
					if (count >= (LATENCY - 1)) begin
						state_w = INIT;
					end
				end else begin
					if (count >= (LATENCY - 2)) begin
						state_w = READ_READY;
					end
				end
			end
		`endif
		default: ;
	endcase
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state <= 'd0;
		o_valid <= 1'b0;
		`ifndef SYNTHESIS
			count <= 'd0;
		`endif
	end else begin
		state <= state_w;
		o_valid <= o_valid_w;
		`ifndef SYNTHESIS
			count <= count_w;
		`endif
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		i_rdata <= 'd0;
		o_r0w1 <= 'd0;
		o_rwaddr <= 'd0;
		o_wdata <= 'd0;
		for (int i = 0; i < NUM_SET; i++) begin
			for (int j = 0; j < ASSOCITIVITY; j++) begin
				tags[i][j] <= 'd0;
				for (int k = 0; k < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; k++) begin
					data[i][j][k] <= 'd0;
				end
			end
		end
		for (int i = 0; i < NUM_SET; i++) begin
			dirty[i] <= 'd0;
			for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
				valid[i][j] <= 'd0;
			end
		end
	end else begin
		i_rdata <= i_rdata_w;
		o_r0w1 <= o_r0w1_w;
		o_rwaddr <= o_rwaddr_w;
		o_wdata <= o_wdata_w;
		for (int i = 0; i < NUM_SET; i++) begin
			for (int j = 0; j < ASSOCITIVITY; j++) begin
				tags[i][j] <= tags_w[i][j];
				for (int k = 0; k < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; k++) begin
					data[i][j][k] <= data_w[i][j][k];
				end
			end
		end
		for (int i = 0; i < NUM_SET; i++) begin
			dirty[i] <= dirty_w[i];
			for (int j = 0; j < NUM_LAST_BLOCK_PER_CURRENT_BLOCK; j++) begin
				valid[i][j] <= valid_w[i][j];
			end
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < NUM_SET; i++) begin
			clock[i] <= {{(ASSOCITIVITY-1){1'b0}}, 1'b1};
			clock_use[i] <= 'd0;
		end
	end else if (i_valid && i_ready) begin
		for (int i = 0; i < NUM_SET; i++) begin
			clock[i] <= clock_w[i];
			clock_use[i] <= clock_use_w[i];
		end
	end
end

always@(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		s1_evicted_tag <= 'd0;
		s1_evicted_block_mask <= 'd0;
		s1_r0w1 <= 1'b0;
		s1_rwaddr <= 'd0;
		s1_wdata <= 'd0;
		s1_tag <= 'd0;
		s1_index <= 'd0;
		s1_offset <= 'd0;
		s1_written_block_mask_when_miss <= 'd0;
	end else if (state == INIT && i_valid) begin
		s1_evicted_tag <= i_evicted_tag;
		s1_evicted_block_mask <= i_evicted_block_mask;
		s1_r0w1 <= i_r0w1;
		s1_rwaddr <= i_rwaddr;
		s1_wdata <= i_wdata;
		s1_tag <= i_tag;
		s1_index <= i_index;
		s1_offset <= i_offset;
		s1_written_block_mask_when_miss <= i_written_block_mask_when_miss;
	end
end
endmodule
`endif