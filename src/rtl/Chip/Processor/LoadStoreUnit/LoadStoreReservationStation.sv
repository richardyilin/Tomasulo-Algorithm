`ifndef __LOADSTORERESERVATIONSTATION_SV__
`define __LOADSTORERESERVATIONSTATION_SV__

`include "../rtl/common/Define.sv"
`include "../rtl/common/Controller.sv"
`include "../rtl/common/BitOperation.sv"
module LoadStoreReservationStation#(
	parameter BW_PROCESSOR_DATA = 32,
	parameter NUM_LOAD_RESERVATION_STATION = 5,
	parameter NUM_STORE_RESERVATION_STATION = 5,
	parameter AQ_LENGTH = 10,
	parameter BW_TAG = 1,
	parameter BW_ADDRESS = 32
)(
	input clk,
	input rst_n,
//----------From Instruction Queue----------
	`twowire_input(i_iq),
	input [BW_TAG-1:0] i_iq_tag,
	input [2*BW_TAG-1:0] i_iq_Q_flatten,
	input signed [2*BW_PROCESSOR_DATA-1:0] i_iq_V_flatten,
	input signed [11:0] i_iq_imm,
	input i_iq_opcode, // 1 is store, 0 is load
	input i_iq_speculation,

//----------Speculation----------
	`onewire_input(i_branch),
	input i_branch_correct_prediction,

//----------From Common Data Bus----------
	`onewire_input(i_cdb),
	input [BW_TAG-1:0] i_cdb_tag,
	input signed [BW_PROCESSOR_DATA-1:0] i_cdb_data,

//----------To Memory Unit----------
	`twowire_output(o_mu),
	output logic [BW_TAG-1:0] o_mu_tag,
	output logic o_mu_opcode, // r = 0, w = 1
	output logic [BW_ADDRESS-1:0] o_mu_rwaddr,
	output logic signed [BW_PROCESSOR_DATA-1:0] o_mu_wdata
);

logic [BW_TAG-1:0] i_iq_Q[2];
logic signed [BW_PROCESSOR_DATA-1:0] i_iq_V[2];
always @(*) begin
	for (int i = 0; i < 2; i++) begin
		i_iq_Q[i] = i_iq_Q_flatten[i*BW_TAG +: BW_TAG];
		i_iq_V[i] = i_iq_V_flatten[i*BW_PROCESSOR_DATA +: BW_PROCESSOR_DATA];
	end
end

localparam MAX_RSV_NUM = (NUM_LOAD_RESERVATION_STATION > NUM_STORE_RESERVATION_STATION) ? NUM_LOAD_RESERVATION_STATION : NUM_STORE_RESERVATION_STATION;
localparam BW_RSV_TAG = $clog2(MAX_RSV_NUM);
localparam BW_FIFO = BW_RSV_TAG + 12 + 1;
localparam SELECT_LOAD = 0;
localparam SELECT_STORE = 1;
localparam SELECT_NONE = 2;

typedef logic[MAX_RSV_NUM-1:0] QueueTagMaskType;

`twowire_logic(i_fifo);
`twowire_logic(o_fifo);
logic [AQ_LENGTH-1:0] fifo_load_in;
logic [AQ_LENGTH-2:0] fifo_forward;
AddressQueueSpeculationController #(
	.N(AQ_LENGTH)
) u_address_queue (
	.clk(clk),
	.rst_n(rst_n),
	`twowire_connect(i, i_fifo),
	`twowire_connect(o, o_fifo),
	`onewire_connect(i_branch, i_branch),
	.i_branch_correct_prediction(i_branch_correct_prediction),
	.i_iq_speculation(i_iq_speculation),
	.o_load_in(fifo_load_in),
	.o_forward(fifo_forward)
);

logic [BW_TAG-1:0] aq_Q[AQ_LENGTH], aq_Q_w[3][AQ_LENGTH];
assign o_fifo_ready = aq_Q[0] == 'd0;

logic [BW_FIFO-1:0] address_queue_w[AQ_LENGTH-1], address_queue[AQ_LENGTH];
logic [BW_FIFO-1:0] i_aq_data;

logic signed [BW_PROCESSOR_DATA-1:0] aq_V[AQ_LENGTH], aq_V_w[3][AQ_LENGTH];
logic [BW_RSV_TAG-1:0] i_aq_rsv_tag, o_aq_rsv_tag;
logic [MAX_RSV_NUM-1:0] o_aq_rsv_tag_mask;
logic signed [11:0] o_aq_imm;
logic o_aq_opcode;
logic [MAX_RSV_NUM-1:0] i_aq_rsv_tag_mask;
logic [NUM_LOAD_RESERVATION_STATION-1:0] i_aq_selected_lrsv_handshake;
logic [NUM_STORE_RESERVATION_STATION-1:0] i_aq_selected_srsv_handshake;
logic [BW_ADDRESS-1:0] o_aq_address;
logic signed [BW_ADDRESS-1:0] o_aq_imm_extended;
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_aq_load_bit_vector;
logic [NUM_STORE_RESERVATION_STATION-1:0] o_aq_store_bit_vector;
assign i_aq_rsv_tag_mask = (i_iq_opcode == `LOAD) ? QueueTagMaskType'(i_aq_selected_lrsv_handshake) : QueueTagMaskType'(i_aq_selected_srsv_handshake);
assign i_aq_data = {i_aq_rsv_tag, i_iq_imm, i_iq_opcode};
assign {o_aq_rsv_tag, o_aq_imm, o_aq_opcode} = address_queue[0];
assign o_aq_imm_extended = {{20{o_aq_imm[11]}}, o_aq_imm};
assign o_aq_address = aq_V[0] + o_aq_imm_extended;
assign o_aq_rsv_tag_mask = 'd1 << o_aq_rsv_tag;

Onehot2Binary #(
	.N(MAX_RSV_NUM)
) u_oh2b (
	.i(i_aq_rsv_tag_mask),
	.o(i_aq_rsv_tag)
);

always @(*) begin
	for (int i = 0; i < AQ_LENGTH; i++) begin
		// load data from IQ
		aq_Q_w[0][i] = fifo_load_in[i] ? i_iq_Q[0] : aq_Q[i];
		aq_V_w[0][i] = fifo_load_in[i] ? i_iq_V[0] : aq_V[i];
		// update with CDB
		if (i_cdb_valid && aq_Q_w[0][i] == i_cdb_tag) begin
			aq_Q_w[1][i] = 'd0;
			aq_V_w[1][i] = i_cdb_data;
		end else begin
			aq_Q_w[1][i] = aq_Q_w[0][i];
			aq_V_w[1][i] = aq_V_w[0][i];
		end
	end
	aq_Q_w[2][AQ_LENGTH-1] = aq_Q_w[1][AQ_LENGTH-1];
	for (int i = 0; i < AQ_LENGTH-1; i++) begin
		// forward data
		aq_Q_w[2][i] = fifo_forward[i] ? aq_Q_w[1][i+1] : aq_Q_w[1][i];
		aq_V_w[2][i] = fifo_forward[i] ? aq_V_w[1][i+1] : aq_V_w[1][i];
	end
end
genvar gi;
generate
	for (gi = 0; gi < AQ_LENGTH-1; gi=gi+1) begin
		always@(posedge clk or negedge rst_n) begin
			if(!rst_n) begin
				aq_Q[gi] <= 'd0;
				aq_V[gi] <= 'd0;
			end else if(fifo_load_in[gi] || fifo_forward[gi] || i_cdb_valid) begin
				aq_Q[gi] <= aq_Q_w[2][gi];
				aq_V[gi] <= aq_V_w[2][gi];
			end
		end
	end
endgenerate
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		aq_Q[AQ_LENGTH-1] <= 'd0;
		aq_V[AQ_LENGTH-1] <= 'd0;
	end else if(fifo_load_in[AQ_LENGTH-1] || i_cdb_valid) begin
		aq_Q[AQ_LENGTH-1] <= aq_Q[2][AQ_LENGTH-1];
		aq_V[AQ_LENGTH-1] <= aq_V[2][AQ_LENGTH-1];
	end
end
always@(*) begin
	for (int i = 0; i < AQ_LENGTH-1; i++) begin
		address_queue_w[i] = fifo_load_in[i] ? i_aq_data : address_queue[i+1];
	end
end
genvar gi2;
generate
	for (gi2 = 0; gi2 < AQ_LENGTH-1; gi2=gi2+1) begin
		always@(posedge clk or negedge rst_n) begin
			if(!rst_n) begin
				address_queue[gi2] <= 'd0;
			end else if(fifo_load_in[gi2] || fifo_forward[gi2]) begin
				address_queue[gi2] <= address_queue_w[gi2];
			end
		end
	end
endgenerate
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		address_queue[AQ_LENGTH-1] <= 'd0;
	end else if(fifo_load_in[AQ_LENGTH-1]) begin
		address_queue[AQ_LENGTH-1] <= i_aq_data;
	end
end
// For RSV: bit_vector, address, valid, address_valid, tag, Q, V when handshake with IQ, address, bit_vector when handshake with fifo output
logic [BW_TAG-1:0] o_Q_srsv[NUM_STORE_RESERVATION_STATION], i_Q_srsv[2][NUM_STORE_RESERVATION_STATION]; // srsv means store reservation station
logic signed [BW_PROCESSOR_DATA-1:0] o_V_srsv[NUM_STORE_RESERVATION_STATION], i_V_srsv[2][NUM_STORE_RESERVATION_STATION];
logic [BW_TAG-1:0] o_tag_srsv[NUM_STORE_RESERVATION_STATION], i_tag_srsv[NUM_STORE_RESERVATION_STATION];
logic [BW_ADDRESS-1:0] o_address_srsv[NUM_STORE_RESERVATION_STATION], i_address_srsv[NUM_STORE_RESERVATION_STATION];
logic [NUM_STORE_RESERVATION_STATION-1:0] o_address_valid_srsv, i_address_valid_srsv[3];
logic [NUM_STORE_RESERVATION_STATION-1:0] o_valid_srsv, i_valid_srsv[2];
logic [NUM_STORE_RESERVATION_STATION-1:0] o_mu_selected_store;
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_bit_vector_load_srsv[NUM_STORE_RESERVATION_STATION], i_bit_vector_load_srsv[2][NUM_STORE_RESERVATION_STATION];
logic [NUM_STORE_RESERVATION_STATION-1:0] o_bit_vector_store_srsv[NUM_STORE_RESERVATION_STATION], i_bit_vector_store_srsv[2][NUM_STORE_RESERVATION_STATION];
logic [NUM_STORE_RESERVATION_STATION-1:0] o_ready_srsv;
logic [NUM_STORE_RESERVATION_STATION-1:0] i_available_srsv;
logic [NUM_STORE_RESERVATION_STATION:0] i_aq_selected_extended_srsv;
logic [NUM_STORE_RESERVATION_STATION-1:0] o_mu_selected_srsv;
logic [NUM_STORE_RESERVATION_STATION-1:0] o_mu_selected_srsv_handshake;
logic [NUM_STORE_RESERVATION_STATION:0] o_mu_selected_extended_srsv;
logic [BW_TAG-1:0] o_mu_selected_tag_srsv;
logic [BW_ADDRESS-1:0] o_mu_selected_address_srsv;
logic [NUM_STORE_RESERVATION_STATION-1:0] o_speculation_srsv, i_speculation_srsv;

logic [BW_TAG-1:0] o_tag_lrsv[NUM_LOAD_RESERVATION_STATION], i_tag_lrsv[NUM_LOAD_RESERVATION_STATION];
logic [BW_ADDRESS-1:0] o_address_lrsv[NUM_LOAD_RESERVATION_STATION], i_address_lrsv[NUM_LOAD_RESERVATION_STATION];
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_address_valid_lrsv, i_address_valid_lrsv[3];
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_valid_lrsv, i_valid_lrsv[2];
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_mu_selected_load;
logic [NUM_STORE_RESERVATION_STATION-1:0] o_bit_vector_store_lrsv[NUM_LOAD_RESERVATION_STATION], i_bit_vector_store_lrsv[2][NUM_LOAD_RESERVATION_STATION];
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_ready_lrsv;
logic [NUM_LOAD_RESERVATION_STATION-1:0] i_available_lrsv;
logic [NUM_LOAD_RESERVATION_STATION:0] i_aq_selected_extended_lrsv;
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_mu_selected_lrsv;
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_mu_selected_lrsv_handshake;
logic [NUM_LOAD_RESERVATION_STATION:0] o_mu_selected_extended_lrsv;
logic [BW_TAG-1:0] o_mu_selected_tag_lrsv;
logic [BW_ADDRESS-1:0] o_mu_selected_address_lrsv;
logic [NUM_LOAD_RESERVATION_STATION-1:0] o_speculation_lrsv, i_speculation_lrsv;

logic [NUM_STORE_RESERVATION_STATION+NUM_LOAD_RESERVATION_STATION-1:0] i_valid;
logic [NUM_STORE_RESERVATION_STATION+NUM_LOAD_RESERVATION_STATION:0] i_selected;
logic [1:0] o_selection; // 1 if store is selected, 0 if load is selected, 2 if no one is selected
logic o_mu_lrsv_handshake, o_mu_srsv_handshake;
logic o_aq_lrsv_handshake, o_aq_srsv_handshake;
logic i_aq_lrsv_handshake, i_aq_srsv_handshake;
FindFromLsb #(.N(NUM_LOAD_RESERVATION_STATION)
) u_iq_select_lrsv (
	.i_data(i_available_lrsv),
	.o_cumsum(),
	.o_position(i_aq_selected_extended_lrsv)
);
RoundRobin#(
	.NUM_CANDIDATE(NUM_LOAD_RESERVATION_STATION)
) u_mu_select_lrsv (
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(o_ready_lrsv),
	.o_chosen(o_mu_selected_extended_lrsv),
	.i_handshake(o_mu_lrsv_handshake)
);

FindFromLsb #(.N(NUM_STORE_RESERVATION_STATION)
) u_iq_select_srsv (
	.i_data(i_available_srsv),
	.o_cumsum(),
	.o_position(i_aq_selected_extended_srsv)
);
RoundRobin#(
	.NUM_CANDIDATE(NUM_STORE_RESERVATION_STATION)
) u_mu_select_srsv (
	.clk(clk),
	.rst_n(rst_n),
	.i_valid(o_ready_srsv),
	.o_chosen(o_mu_selected_extended_srsv),
	.i_handshake(o_mu_srsv_handshake)
);
always @(*) begin
	i_aq_lrsv_handshake = 1'b0;
	i_aq_srsv_handshake = 1'b0;
	if (i_iq_opcode == `LOAD) begin // input is load
		i_fifo_valid = i_iq_valid && !i_aq_selected_extended_lrsv[NUM_LOAD_RESERVATION_STATION]; // if i_iq is valid and there is place for load reservation station, queue will take new input if queue has a place
		i_aq_lrsv_handshake = `handshake(i_fifo);
	end else begin
		i_fifo_valid = i_iq_valid && !i_aq_selected_extended_srsv[NUM_STORE_RESERVATION_STATION];
		i_aq_srsv_handshake = `handshake(i_fifo);
	end
	i_iq_ready = `handshake(i_fifo);
	// load output part
	for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
		o_ready_lrsv[i] = (o_bit_vector_store_lrsv[i] == 'd0) && o_address_valid_lrsv[i] && o_valid_lrsv[i] && !o_speculation_lrsv[i]; // bit vector is cleared and valid
	end
	o_mu_selected_lrsv = o_mu_selected_extended_lrsv[NUM_LOAD_RESERVATION_STATION-1:0];
	o_mu_selected_tag_lrsv = 'd0;
	o_mu_selected_address_lrsv = 'd0;
	for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
		o_mu_selected_tag_lrsv = o_mu_selected_tag_lrsv | (o_mu_selected_lrsv[i] ? o_tag_lrsv[i] : 'd0);
		o_mu_selected_address_lrsv = o_mu_selected_address_lrsv | (o_mu_selected_lrsv[i] ? o_address_lrsv[i] : 'd0);
	end
	// store output part
	for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
		o_ready_srsv[i] = (o_bit_vector_store_srsv[i] == 'd0) && (o_bit_vector_load_srsv[i] == 'd0) && o_address_valid_srsv[i] && (o_Q_srsv[i] == 'd0) && o_valid_srsv[i] && !o_speculation_srsv[i]; // bit vector is cleared and Q is 0 and valid
	end
	o_mu_selected_srsv = o_mu_selected_extended_srsv[NUM_STORE_RESERVATION_STATION-1:0];
	o_mu_selected_tag_srsv = 'd0;
	o_mu_selected_address_srsv = 'd0;
	o_mu_wdata = 'd0;
	for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
		o_mu_selected_tag_srsv = o_mu_selected_tag_srsv | (o_mu_selected_srsv[i] ? o_tag_srsv[i] : 'd0);
		o_mu_selected_address_srsv = o_mu_selected_address_srsv | (o_mu_selected_srsv[i] ? o_address_srsv[i] : 'd0);
		o_mu_wdata = o_mu_wdata | (o_mu_selected_srsv[i] ? o_V_srsv[i] : 'd0);
	end
	if (!o_mu_selected_extended_lrsv[NUM_LOAD_RESERVATION_STATION]) begin
		o_selection = SELECT_LOAD;
	end else if (!o_mu_selected_extended_srsv[NUM_STORE_RESERVATION_STATION]) begin
		o_selection = SELECT_STORE;
	end else begin
		o_selection = SELECT_NONE;
	end
	o_mu_valid = 1'b0;
	o_mu_opcode = `LOAD;
	o_mu_tag = o_mu_selected_tag_lrsv;
	o_mu_rwaddr = o_mu_selected_address_lrsv;
	o_mu_lrsv_handshake = 1'b0;
	o_mu_srsv_handshake = 1'b0;
	case (o_selection)
		SELECT_LOAD: begin
			o_mu_valid = 1'b1;
			o_mu_opcode = `LOAD;
			o_mu_tag = o_mu_selected_tag_lrsv;
			o_mu_rwaddr = o_mu_selected_address_lrsv;
			o_mu_lrsv_handshake = `handshake(o_mu);
		end
		SELECT_STORE: begin
			o_mu_valid = 1'b1;
			o_mu_opcode = `STORE;
			o_mu_tag = o_mu_selected_tag_srsv;
			o_mu_rwaddr = o_mu_selected_address_srsv;
			o_mu_srsv_handshake = `handshake(o_mu);
		end
		SELECT_NONE: begin
			o_mu_valid = 1'b0;
		end
		default: ;
	endcase

	// invalidate the one which output to mu
	o_mu_selected_lrsv_handshake = (o_mu_selected_lrsv & ({(NUM_LOAD_RESERVATION_STATION){o_mu_lrsv_handshake}}));
	o_mu_selected_srsv_handshake = (o_mu_selected_srsv & ({(NUM_STORE_RESERVATION_STATION){o_mu_srsv_handshake}}));
	i_valid_lrsv[0] = o_valid_lrsv & (~o_mu_selected_lrsv_handshake);
	i_valid_srsv[0] = o_valid_srsv & (~o_mu_selected_srsv_handshake);
	i_address_valid_lrsv[0] = o_address_valid_lrsv & (~o_mu_selected_lrsv_handshake);
	i_address_valid_srsv[0] = o_address_valid_srsv & (~o_mu_selected_srsv_handshake);

	// add the input from IQ to rsv
	i_available_lrsv = ~i_valid_lrsv[0];
	i_available_srsv = ~i_valid_srsv[0];
	i_aq_selected_lrsv_handshake = i_aq_selected_extended_lrsv[NUM_LOAD_RESERVATION_STATION-1:0] & ({(NUM_LOAD_RESERVATION_STATION){i_aq_lrsv_handshake}});
	i_aq_selected_srsv_handshake = i_aq_selected_extended_srsv[NUM_STORE_RESERVATION_STATION-1:0] & ({(NUM_STORE_RESERVATION_STATION){i_aq_srsv_handshake}});
	i_valid_lrsv[1] = (i_valid_lrsv[0] | i_aq_selected_lrsv_handshake) & (~({(NUM_LOAD_RESERVATION_STATION){i_branch_valid && !i_branch_correct_prediction}} & o_speculation_lrsv));
	i_valid_srsv[1] = (i_valid_srsv[0] | i_aq_selected_srsv_handshake) & (~({(NUM_STORE_RESERVATION_STATION){i_branch_valid && !i_branch_correct_prediction}} & o_speculation_srsv));
	// Speculation
	i_speculation_lrsv = (o_speculation_lrsv | (i_aq_selected_lrsv_handshake & {(NUM_LOAD_RESERVATION_STATION){i_iq_speculation}})) & ({(NUM_LOAD_RESERVATION_STATION){!i_branch_valid}});
	i_speculation_srsv = (o_speculation_srsv | (i_aq_selected_srsv_handshake & {(NUM_STORE_RESERVATION_STATION){i_iq_speculation}})) & ({(NUM_STORE_RESERVATION_STATION){!i_branch_valid}});
	for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
		i_tag_lrsv[i] = i_aq_selected_lrsv_handshake[i] ? i_iq_tag : o_tag_lrsv[i];
	end
	for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
		i_tag_srsv[i] = i_aq_selected_srsv_handshake[i] ? i_iq_tag : o_tag_srsv[i];
		i_Q_srsv[0][i] = i_aq_selected_srsv_handshake[i] ? i_iq_Q[1] : o_Q_srsv[i];
		i_V_srsv[0][i] = i_aq_selected_srsv_handshake[i] ? i_iq_V[1] : o_V_srsv[i];
		if (i_cdb_valid && i_Q_srsv[0][i] == i_cdb_tag) begin // update value from CDB
			i_Q_srsv[1][i] = 'd0;
			i_V_srsv[1][i] = i_cdb_data;
		end else begin
			i_Q_srsv[1][i] = i_Q_srsv[0][i];
			i_V_srsv[1][i] = i_V_srsv[0][i];
		end
	end

	// add bit vector and address from the output of the fifo
	for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
		o_aq_load_bit_vector[i] = (o_aq_address == o_address_lrsv[i]) && o_address_valid_lrsv[i];
	end
	for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
		o_aq_store_bit_vector[i] = (o_aq_address == o_address_srsv[i]) && o_address_valid_srsv[i];
	end
	// add new bit vector for new address
	o_aq_lrsv_handshake = o_aq_opcode == `LOAD && `handshake(o_fifo);
	o_aq_srsv_handshake = o_aq_opcode == `STORE && `handshake(o_fifo);
	for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
		if (o_aq_lrsv_handshake && o_aq_rsv_tag_mask[i]) begin
			i_address_valid_lrsv[1][i] = 1'b1;
			i_address_lrsv[i] = o_aq_address;
			i_bit_vector_store_lrsv[0][i] = o_aq_store_bit_vector;
		end else begin
			i_address_valid_lrsv[1][i] = i_address_valid_lrsv[0][i];
			i_address_lrsv[i] = o_address_lrsv[i];
			i_bit_vector_store_lrsv[0][i] = o_bit_vector_store_lrsv[i];
		end
	end
	for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
		if (o_aq_srsv_handshake && o_aq_rsv_tag_mask[i]) begin
			i_address_valid_srsv[1][i] = 1'b1;
			i_address_srsv[i] = o_aq_address;
			i_bit_vector_load_srsv[0][i] = o_aq_load_bit_vector;
			i_bit_vector_store_srsv[0][i] = o_aq_store_bit_vector;
		end else begin
			i_address_valid_srsv[1][i] = i_address_valid_srsv[0][i];
			i_address_srsv[i] = o_address_srsv[i];
			i_bit_vector_load_srsv[0][i] = o_bit_vector_load_srsv[i];
			i_bit_vector_store_srsv[0][i] = o_bit_vector_store_srsv[i];
		end
	end
	i_address_valid_lrsv[2] = i_address_valid_lrsv[1] & (~({(NUM_LOAD_RESERVATION_STATION){i_branch_valid && !i_branch_correct_prediction}} & o_speculation_lrsv));
	i_address_valid_srsv[2] = i_address_valid_srsv[1] & (~({(NUM_STORE_RESERVATION_STATION){i_branch_valid && !i_branch_correct_prediction}} & o_speculation_srsv));
	
	// remove the bit vector resulting from the address that is being removed now
	for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
		for (int j = 0; j < NUM_STORE_RESERVATION_STATION; j++) begin
			if (o_mu_selected_srsv_handshake[j] && (o_address_srsv[j] == i_address_lrsv[i])) begin
				i_bit_vector_store_lrsv[1][i][j] = 1'b0;
			end else begin
				i_bit_vector_store_lrsv[1][i][j] = i_bit_vector_store_lrsv[0][i][j];
			end
		end
	end
	for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
		for (int j = 0; j < NUM_STORE_RESERVATION_STATION; j++) begin
			if (o_mu_selected_srsv_handshake[j] && (o_address_srsv[j] == i_address_srsv[i])) begin
				i_bit_vector_store_srsv[1][i][j] = 1'b0;
			end else begin
				i_bit_vector_store_srsv[1][i][j] = i_bit_vector_store_srsv[0][i][j];
			end
		end
		for (int j = 0; j < NUM_LOAD_RESERVATION_STATION; j++) begin
			if (o_mu_selected_lrsv_handshake[j] && (o_address_lrsv[j] == i_address_srsv[i])) begin
				i_bit_vector_load_srsv[1][i][j] = 1'b0;
			end else begin
				i_bit_vector_load_srsv[1][i][j] = i_bit_vector_load_srsv[0][i][j];
			end
		end
	end
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
			o_address_lrsv[i] <= 'd0;
		end
	end else if(o_aq_lrsv_handshake || o_mu_lrsv_handshake || o_mu_srsv_handshake) begin
		for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
			o_address_lrsv[i] <= i_address_lrsv[i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_address_valid_lrsv <= 'd0;
	end else if(o_aq_lrsv_handshake || o_mu_lrsv_handshake || o_mu_srsv_handshake || i_branch_valid) begin
		o_address_valid_lrsv <= i_address_valid_lrsv[2];
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
			o_bit_vector_store_lrsv[i] <= 'd0;
		end
	end else if(o_aq_lrsv_handshake || o_mu_lrsv_handshake || o_mu_srsv_handshake) begin
		for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
			o_bit_vector_store_lrsv[i] <= i_bit_vector_store_lrsv[1][i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_address_srsv[i] <= 'd0;
		end
	end else if(o_aq_srsv_handshake || o_mu_srsv_handshake) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_address_srsv[i] <= i_address_srsv[i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_address_valid_srsv <= 'd0;
	end else if(o_aq_srsv_handshake || o_mu_srsv_handshake || i_branch_valid) begin
		o_address_valid_srsv <= i_address_valid_srsv[2];
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_bit_vector_load_srsv[i] <= 'd0;
			o_bit_vector_store_srsv[i] <= 'd0;
		end
	end else if(o_aq_lrsv_handshake || o_mu_lrsv_handshake || o_mu_srsv_handshake) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_bit_vector_load_srsv[i] <= i_bit_vector_load_srsv[1][i];
			o_bit_vector_store_srsv[i] <= i_bit_vector_store_srsv[1][i];
		end
	end
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_valid_lrsv <= 'd0;
	end else if(i_aq_lrsv_handshake || o_mu_lrsv_handshake || i_branch_valid) begin
		o_valid_lrsv <= i_valid_lrsv[1];
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
			o_tag_lrsv[i] <= 'd0;
		end
	end else if(i_aq_lrsv_handshake) begin
		for (int i = 0; i < NUM_LOAD_RESERVATION_STATION; i++) begin
			o_tag_lrsv[i] <= i_tag_lrsv[i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_valid_srsv <= 'd0;
	end else if(i_aq_srsv_handshake || o_mu_srsv_handshake || i_branch_valid) begin
		o_valid_srsv <= i_valid_srsv[1];
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_tag_srsv[i] <= 'd0;
		end
	end else if(i_aq_srsv_handshake) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_tag_srsv[i] <= i_tag_srsv[i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_Q_srsv[i] <= 'd0;
			o_V_srsv[i] <= 'd0;
		end
	end else if(i_cdb_valid || i_aq_srsv_handshake) begin
		for (int i = 0; i < NUM_STORE_RESERVATION_STATION; i++) begin
			o_Q_srsv[i] <= i_Q_srsv[1][i];
			o_V_srsv[i] <= i_V_srsv[1][i];
		end
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_speculation_lrsv <= 'd0;
	end else if(i_aq_lrsv_handshake || i_branch_valid) begin
		o_speculation_lrsv <= i_speculation_lrsv;
	end
end
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		o_speculation_srsv <= 'd0;
	end else if(i_aq_srsv_handshake || i_branch_valid) begin
		o_speculation_srsv <= i_speculation_srsv;
	end
end
endmodule
`endif