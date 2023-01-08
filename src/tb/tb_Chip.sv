`timescale 1 ns/100 ps

`include "../rtl/common/Define.sv"
`include "../rtl/Chip.sv"
`include "../rtl/Memory.sv"
`define CYCLE 10 // You can modify your clock frequency
`define INPUT_DELAY     0.3
`define END_CYCLE 1000000

`define hasHazard

`ifdef hasHazard
	`define IMEM_INIT "./test_cases/I_mem_hasHazard.txt"
	`define DMEM_INIT "./test_cases/D_mem"
	`define READ_MEM_DATA $readmemb
	`define TestPort    30'hFF
`endif	
`ifdef BrPred
	`define IMEM_INIT "./test_cases/I_mem_BrPred.txt"
	`define DMEM_INIT "./test_cases/D_mem"
	`define READ_MEM_DATA $readmemb
	`define TestPort    30'h0
`endif
`ifdef L2Cache
	`define IMEM_INIT "./test_cases/I_mem_L2Cache.txt"
	`define DMEM_INIT "./test_cases/D_mem"
	`define READ_MEM_DATA $readmemb
	`define TestPort    30'h3FF
`endif
`ifdef leaf
    `define IMEM_INIT "./test_cases/leaf/leaf_text.txt"
    `define DMEM_INIT "./test_cases/leaf/leaf_data.txt"
	`define READ_MEM_DATA $readmemh
    `define MEM_DATA_ANS "./test_cases/leaf/leaf_data_ans.txt"
`endif

`ifdef fact
    `define IMEM_INIT "./test_cases/fact/fact_text.txt"
    `define DMEM_INIT "./test_cases/fact/fact_data.txt"
	`define READ_MEM_DATA $readmemh
    `define MEM_DATA_ANS "./test_cases/fact/fact_data_ans.txt"
`endif

`ifdef recursion
    `define IMEM_INIT "./test_cases/recursion/recursion_text.txt"
    `define DMEM_INIT "./test_cases/recursion/recursion_data.txt"
	`define READ_MEM_DATA $readmemh
    `define MEM_DATA_ANS "./test_cases/recursion/recursion_data_ans.txt"
`endif

module tb_Chip;

	// Abbreviation list:
	//  - BW = bitwidth
	//  - NUM = number
	parameter BW_ADDRESS = 32;
	parameter BW_PROCESSOR_BLOCK = 128;


	parameter L1_LATENCY = 4;
	parameter L1_ASSOCITIVITY = 2;
	parameter L1_NUM_SET = 4;
	parameter L1_BW_BLOCK = 128;

	`ifdef L2
		
		parameter L2_LATENCY = 12;
		parameter L2_ASSOCITIVITY = 4;
		parameter L2_NUM_SET = 16;
		parameter L2_BW_BLOCK = 512;

	`endif
	
	parameter MEMORY_LATENCY = 100;

	parameter NUM_KINDS_OF_RESERVATION_STATION = 5;
	parameter NUM_KINDS_OF_UNIT = 4;

	parameter [BW_ADDRESS+4:0] MEMORY_SIZE = (1 << 12) * `BYTE;
	parameter BW_PROCESSOR_DATA = 32;
	parameter IQ_LENGTH = 100;
	parameter NUM_INT_RESERVATION_STATION = 4;
	parameter NUM_MUL_RESERVATION_STATION = 4;
	parameter NUM_LOAD_RESERVATION_STATION = 4;
	parameter NUM_STORE_RESERVATION_STATION = 4;
	parameter BW_TAG = $clog2(NUM_INT_RESERVATION_STATION + NUM_MUL_RESERVATION_STATION + NUM_LOAD_RESERVATION_STATION + NUM_STORE_RESERVATION_STATION + NUM_KINDS_OF_UNIT + 10);
	parameter BW_OPCODE_BRANCH = 3;
	parameter BW_OPCODE_INT = 4;

	parameter NUM_GLOBAL_HISTORY = 2;
	parameter BW_SELECTED_PC = 10;
	parameter NUM_BTB = 64;
	parameter AQ_LENGTH = 10;

	logic clk;
	logic rst_n;

	localparam IMEM_SIZE = MEMORY_SIZE / 32;
	localparam DMEM_SIZE = MEMORY_SIZE / 32;
	localparam BW_INST_INDEX = $clog2(IMEM_SIZE);
	localparam NUM_WRITE = 1024;
	localparam NUM_STORE_UPPERBOUND = 1024;
	localparam NUM_GLOBAL_HISTORY_ENTRY = 1 << NUM_GLOBAL_HISTORY;
	localparam NUM_LOCAL_HISTORY_ENTRY = 1 << BW_SELECTED_PC;

	logic [BW_ADDRESS-1:0] PC;
	logic [BW_INST_INDEX-1:0] i_cache_index;
	logic [31:0] i_cache [IMEM_SIZE];
	logic [31:0] inst;
	logic [BW_PROCESSOR_DATA-1:0] memory [DMEM_SIZE];
	logic [$clog2(IMEM_SIZE)-1:0] eof;
	logic [4:0] rs1, rs2, rd;
	logic [BW_PROCESSOR_DATA-1:0] reg_file [32];
	logic signed [BW_PROCESSOR_DATA-1:0] V1, V2, result;
	logic [2:0] funct3;
	logic [6:0] funct7;
	logic [4:0] opcode;
	logic [31:0] u_imm;
	logic signed [31:0] imm;
	logic [4:0] shamt;
	logic [BW_PROCESSOR_DATA-1:0] load_word;
	logic [BW_PROCESSOR_DATA-1:0] store_word;
	logic [BW_ADDRESS-1:0] address;
	logic [BW_ADDRESS-2-1:0] memory_index;
	logic [$clog2(NUM_STORE_UPPERBOUND+1)-1:0] store_count, dut_store_count;
	logic [BW_ADDRESS-3:0] store_address [NUM_STORE_UPPERBOUND], dut_store_address [NUM_STORE_UPPERBOUND];
	logic [BW_PROCESSOR_DATA-1:0] store_value [NUM_STORE_UPPERBOUND], dut_store_value [NUM_STORE_UPPERBOUND];

	logic I_mem_ready;
	`ifdef L2
		logic [L2_BW_BLOCK-1:0] I_mem_rdata;
	`else
		logic [L1_BW_BLOCK-1:0] I_mem_rdata;
	`endif
    logic I_mem_valid;
	logic I_mem_r0w1;
	logic [BW_ADDRESS-1:0] I_mem_rwaddr;
	`ifdef L2
		logic [L2_BW_BLOCK-1:0] I_mem_wdata;
	`else
		logic [L1_BW_BLOCK-1:0] I_mem_wdata;
	`endif

//----------for data memory------------
	logic D_mem_ready;
	`ifdef L2
		logic [L2_BW_BLOCK-1:0] D_mem_rdata;
	`else
		logic [L1_BW_BLOCK-1:0] D_mem_rdata;
	`endif
    logic D_mem_valid;
	logic D_mem_r0w1;
	logic [BW_ADDRESS-1:0] D_mem_rwaddr;
	`ifdef L2
		logic [L2_BW_BLOCK-1:0] D_mem_wdata;
	`else
		logic [L1_BW_BLOCK-1:0] D_mem_wdata;
	`endif
//----------for testbench--------------
    logic D_cache_wen;
    logic [BW_ADDRESS-1:0] D_cache_addr;
    logic [BW_PROCESSOR_DATA-1:0] D_cache_wdata;

	Chip#(
		.BW_PROCESSOR_BLOCK(BW_PROCESSOR_BLOCK),
		.BW_PROCESSOR_DATA(BW_PROCESSOR_DATA),
		.NUM_GLOBAL_HISTORY(NUM_GLOBAL_HISTORY),
		.BW_SELECTED_PC(BW_SELECTED_PC),
		.NUM_BTB(NUM_BTB),
		.IQ_LENGTH(IQ_LENGTH),
		.NUM_KINDS_OF_RESERVATION_STATION(NUM_KINDS_OF_RESERVATION_STATION),
		.NUM_KINDS_OF_UNIT(NUM_KINDS_OF_UNIT),
		.NUM_INT_RESERVATION_STATION(NUM_INT_RESERVATION_STATION),
		.NUM_MUL_RESERVATION_STATION(NUM_MUL_RESERVATION_STATION),
		.NUM_LOAD_RESERVATION_STATION(NUM_LOAD_RESERVATION_STATION),
		.NUM_STORE_RESERVATION_STATION(NUM_STORE_RESERVATION_STATION),
		.BW_TAG(BW_TAG),
		.BW_OPCODE_BRANCH(BW_OPCODE_BRANCH),
		.BW_OPCODE_INT(BW_OPCODE_INT),
		.BW_ADDRESS(BW_ADDRESS),
		.AQ_LENGTH(AQ_LENGTH),
		`ifdef L2
			.L2_LATENCY(L2_LATENCY),
			.L2_ASSOCITIVITY(L2_ASSOCITIVITY),
			.L2_NUM_SET(L2_NUM_SET),
			.L2_BW_BLOCK(L2_BW_BLOCK),
		`endif
        .L1_LATENCY(L1_LATENCY),
        .L1_ASSOCITIVITY(L1_ASSOCITIVITY),
        .L1_NUM_SET(L1_NUM_SET),
        .L1_BW_BLOCK(L1_BW_BLOCK)
	) u_chip (
		
		.clk(clk),
		.rst_n(rst_n),

	//----------for instruction memory------------
		.I_mem_ready(I_mem_ready),
		.I_mem_rdata(I_mem_rdata),
		.I_mem_valid(I_mem_valid),
		.I_mem_r0w1(I_mem_r0w1), // r = 0, w = 1
		.I_mem_rwaddr(I_mem_rwaddr),
		.I_mem_wdata(I_mem_wdata),

	//----------for data memory------------
		.D_mem_ready(D_mem_ready),
		.D_mem_rdata(D_mem_rdata),
		.D_mem_valid(D_mem_valid),
		.D_mem_r0w1(D_mem_r0w1), // r = 0, w = 1
		.D_mem_rwaddr(D_mem_rwaddr),
		.D_mem_wdata(D_mem_wdata),
	//----------for testbench--------------
		.D_cache_wen(D_cache_wen),
		.D_cache_addr(D_cache_addr),
		.D_cache_wdata(D_cache_wdata)
	);
	Memory#(
		.BW_ADDRESS(BW_ADDRESS),
		.MEMORY_LATENCY(MEMORY_LATENCY),
		`ifdef L2
		.BW_LAST_BLOCK(L2_BW_BLOCK),
		`else
		.BW_LAST_BLOCK(L1_BW_BLOCK),
		`endif
		.MEMORY_SIZE(MEMORY_SIZE)
	) u_i_mem (
		.clk(clk),
		.rst_n(rst_n),
		.i_valid(I_mem_valid),
		.i_r0w1(I_mem_r0w1), // r = 0, w = 1
		.i_rwaddr(I_mem_rwaddr),
		.i_wdata(I_mem_wdata),
		.o_ready(I_mem_ready),
		.o_rdata(I_mem_rdata)
	);

	Memory#(
		.BW_ADDRESS(BW_ADDRESS),
		.MEMORY_LATENCY(MEMORY_LATENCY),
		`ifdef L2
		.BW_LAST_BLOCK(L2_BW_BLOCK),
		`else
		.BW_LAST_BLOCK(L1_BW_BLOCK),
		`endif
		.MEMORY_SIZE(MEMORY_SIZE)
	) u_d_mem (
		.clk(clk),
		.rst_n(rst_n),
		.i_valid(D_mem_valid),
		.i_r0w1(D_mem_r0w1),
		.i_rwaddr(D_mem_rwaddr),
		.i_wdata(D_mem_wdata),
		.o_ready(D_mem_ready),
		.o_rdata(D_mem_rdata)
	);
	
	always #(`CYCLE*0.5) clk = ~clk;
    initial begin            
        $dumpfile("wave.fst");       
        $dumpvars(0, tb_Chip);
    end
	integer tb_index;
	logic D_mem_handshake;
	integer pc_count;
	assign D_mem_handshake = `handshake(D_mem);

	initial begin
		$display("-----------------------------------------------------\n");
	 	$display("START!!! Simulation Start .....\n");
	 	$display("-----------------------------------------------------\n");

		for (int i = 0; i < DMEM_SIZE; i++) begin
			memory[i] = 'd0;
		end
		`READ_MEM_DATA (`DMEM_INIT, memory ); // initialize data in DMEM
		$readmemh (`IMEM_INIT, i_cache ); // initialize data in IMEM
		`ifdef L2
			for (int i = 0; i < MEMORY_SIZE / L2_BW_BLOCK; i++) begin
				for (int j = 0; j < L2_BW_BLOCK / 32; j++) begin
					tb_index = i * (L2_BW_BLOCK / 32) + j;
					u_i_mem.memory[i][j*32 +: 32] = i_cache[tb_index];
					u_d_mem.memory[i][j*32 +: 32] = memory[tb_index];
				end
			end
		`else
			for (int i = 0; i < MEMORY_SIZE / L1_BW_BLOCK; i++) begin
				for (int j = 0; j < L1_BW_BLOCK / 32; j++) begin
					tb_index = i * (L1_BW_BLOCK / 32) + j;
					u_i_mem.memory[i][j*32 +: 32] = i_cache[tb_index];
					u_d_mem.memory[i][j*32 +: 32] = memory[tb_index];
				end
			end
		`endif
		i_cache_index = 0;
		while (i_cache[i_cache_index] !== 32'bx) begin
            i_cache_index = i_cache_index + 1;
		end
		eof = i_cache_index * 4;
		PC = 'd0;
		store_count = 0;
		for (int i = 0; i < 32; i++) begin
			reg_file[i] = 'd0;
		end
		pc_count = 0;
		while (PC < eof) begin
			reg_file[0] = 0;
			i_cache_index = PC[BW_INST_INDEX+1:2];
			inst = i_cache[i_cache_index];
			rs1 = inst[19:15];
			rs2 = inst[24:20];
			rd = inst[11:7];
			funct3 = inst[14:12];
			funct7 = inst[31:25];
			opcode = inst[6:2];
			V1 = reg_file[rs1];
			V2 = reg_file[rs2];
			case (opcode)
				5'b01100: begin // R-type
					if (funct7 == 7'b0000001) begin // mul or div
						case (funct3)
							3'b000: begin // mul
								result = V1 * V2;
							end
							3'b100: begin
								result = V1 / V2;
							end
						endcase
					end else begin
						case (funct3)
							3'b000: begin
								case (funct7)
									7'b0000000: begin // add
										result = V1 + V2;
									end
									7'b0100000: begin
										result = V1 - V2;
									end
								endcase
							end 
							3'b010: begin // SLT
								result = (V1 < V2) ? 'd1 : 'd0;
							end
							3'b100: begin // xor
								result = V1 ^ V2;
							end
							3'b110: begin // or
								result = V1 | V2;
							end
							3'b111: begin // and
								result = V1 & V2;
							end
						endcase
					end
					reg_file[rd] = result;
					PC = PC + 4;
				end
				5'b00100: begin // i type
					imm = {{20{inst[31]}}, inst[31:20]};
					shamt = inst[24:20];
					case (funct3)
						3'b000: begin // addi
							result = V1 + imm;
						end
						3'b001: begin// slli
							result = V1 << shamt;
						end
						3'b010: begin // slti
							result = (V1 < imm) ? 'd1 : 'd0;
						end
						3'b100: begin // xori
							result = V1 ^ imm;
						end
						3'b101: begin
							case (funct7)
								7'b0000000: begin // srli
									result = V1 >> shamt;
								end
								7'b0100000: begin // srai
									result = V1 >>> shamt;
								end
							endcase
						end
						3'b110: begin // ori
							result = V1 | imm;
						end
						3'b111: begin // andi
							result = V1 & imm;
						end
					endcase
					reg_file[rd] = result;
					PC = PC + 4;
				end
				5'b01000: begin //sw
					imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
					address = V1 + imm;
					memory_index = address[BW_ADDRESS-1:2];
					store_word = reg_file[rs2];
					memory[memory_index] = store_word;
					`ifdef hasHazard
						if (address[BW_ADDRESS-1:2] == `TestPort) begin //open for brPred, L2Cache, Hashazard
					`elsif BrPred
						if (address[BW_ADDRESS-1:2] == `TestPort) begin //open for brPred, L2Cache, Hashazard
					`elsif L2Cache
						if (address[BW_ADDRESS-1:2] == `TestPort) begin //open for brPred, L2Cache, Hashazard
					`endif
							store_value[store_count] = store_word;
							store_address[store_count] = address[BW_ADDRESS-1:2];
							store_count = store_count + 1;
					`ifdef hasHazard
						end
					`elsif L2Cache
						end
					`elsif BrPred
						end
					`endif
					PC = PC + 4;
				end
				5'b00000: begin // lw
					imm = {{20{inst[31]}}, inst[31:20]};
					address = V1 + imm;
					memory_index = address[BW_ADDRESS-1:2];
					load_word = memory[memory_index];
					reg_file[rd] = load_word;
					PC = PC + 4;
				end
				5'b11000: begin
					imm = {{21{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
					case (funct3)
						3'b000: begin // beq
							if (V1 === V2) begin
								PC = PC + imm;
							end else begin
								PC = PC + 4;
							end
						end
						3'b001: begin // bne
							if (V1 !== V2) begin
								PC = PC + imm;
							end else begin
								PC = PC + 4;
							end
						end
						3'b101: begin // bge
							if (V1 >= V2) begin
								PC = PC + imm;
							end else begin
								PC = PC + 4;
							end
						end
					endcase
					
				end
				5'b11001: begin // jalr
					imm = {{20{inst[31]}}, inst[31:20]};
					reg_file[rd] = PC + 4;
					PC = V1 + imm;
				end
				5'b11011: begin // jal
					imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
					reg_file[rd] = PC + 4;
					PC = PC + imm;
				end
				5'b00101: begin // auipc
					u_imm = {inst[31:12], 12'b0};
					result = PC + u_imm;
					reg_file[rd] = result;
					PC = PC + 4;
				end
        endcase
		pc_count ++;
		end
		$display("TB done\n");
		dut_store_count = 0;
		clk = 0;
		rst_n = 1'b1;
		#(`CYCLE*0.2) rst_n = 1'b0;
		#(`CYCLE*8.5) rst_n = 1'b1;
		$display("reset done\n");

		#(`CYCLE * `END_CYCLE)
		$display("============================================================================");
		$display("\n           Error!!! There is something wrong with your code ...!          ");
		$display("\n                       The test result is .....FAIL                     \n");
		$display("============================================================================");
	 	$finish;

	end
	initial begin
        #(`CYCLE*`END_CYCLE)
		if (error == 0) begin
			$display("error = %d\n",error);
		end
        $display("============================================================\n");
        $display("Simulation time is longer than expected.");
        $display("The test result is .....FAIL :(\n");
        $display("============================================================\n");
        
        $finish;
    end
	logic [31:0] count, error, cycle_count;
	initial begin
		count = 0;
		error = 0;
	end
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			cycle_count <= 'd0;
		end else begin
			cycle_count <= cycle_count + 'd1;
		end
	end
	always @(posedge D_cache_wen) begin
		`ifdef hasHazard
			if (D_cache_addr[BW_ADDRESS-1:2] == `TestPort) begin
		`elsif L2Cache
			if (D_cache_addr[BW_ADDRESS-1:2] == `TestPort) begin
		`elsif BrPred
			if (D_cache_addr[BW_ADDRESS-1:2] == `TestPort) begin
		`endif
			if (store_value[count] !== D_cache_wdata) begin
				error = error + 1;
				$display("error your answer = %d, correct answer = %d, at count = %d error = %d\n",D_cache_wdata, store_value[count], count, error);
			end else begin
				$display("pass count = %d\n", count);
			end
			count = count + 1;
		`ifdef hasHazard
			end
		`elsif L2Cache
			end
		`elsif BrPred
			end
		`endif
		if (count == store_count) begin
			if (error) begin 
				$display("============================================================================");
				$display("\n (T_T) FAIL!! The simulation result is FAIL!!! there were %d errors at all.\n", error);
				$display("============================================================================");
			end
			else begin 
				$display("============================================================================");
				$display("\n \\(^o^)/ CONGRATULATIONS!!  The simulation result is PASS!!!\n");
				$display("============================================================================");
			end
			$display("The execution time is %d cycles\n", cycle_count);
			$finish;
		end
	end
endmodule
