# Tomasulo Algorithm
 
## Introduction
 
   1. This project integrates a RISC-V processor with Tomasulo Algorithm and multilevel caches on a chip. Tomasulo Algorithm enables out-of-order execution with dynamic scheduling of instructions to improve instruction-level parallelism.
   2. Besides Tomasulo Algorithm, this project also adopts a correlating branch predictor and speculation on the processor to improve the performance.
 
## Getting Started
 
### Prerequisites
   This project is run with Icarus Verilog. The SystemVerilog code of this project follows IEEE Standard 1800-2005. To install Icarus Verilog, you can refer to its [installation guide](https://iverilog.fandom.com/wiki/Installation_Guide).
 
### Installation
 
   ```sh
   git clone https://github.com/richardyilin/Tomasulo-Algorithm.git
   ```
### Run the testbench
 
   ```sh
   cd src/tb
   iverilog -g2005-sv -o wave tb_Chip.sv
   vvp -n wave -fst
   ```
   You can change the macro `hasHazard` in [`tb_Chip.sv`](./src/tb/tb_Chip.sv). The options of the macro are `hasHazard`, `BrPred`, `L2Cache`, `leaf`, `fact`, `recursion`. Each option corresponds to six different test cases in the folder [`test_cases`](./src/tb/test_cases).
 
### Usage of macro
 
   1. The macro of this project is in [Define.sv](./src/rtl/common/Define.sv). 
   2. The macro you can change (comment or uncomment) are `L2`, `SYNTHESIS`, and `BRANCH_PREDICTION`. 
   3. With the macro `L2`, caches on the chip are 2-level, otherwise there are only L1 caches. 
   4. With the macro `SYNTHESIS`, the code is synthesizable, otherwise it is for simulation only. 
   5. With the macro `BRANCH_PREDICTION`, the branch prediction is enabled, otherwise the processor always fetches the next instruction at the address of `PC + 4`.
 
 
 
## Reference
   1. Hennessy, John L., and David A. Patterson. Computer architecture: a quantitative approach. Elsevier, 2011.  
   2. Yeh, Tse-Yu, and Yale N. Patt. "Two-level adaptive training branch prediction." Proceedings of the 24th annual international symposium on Microarchitecture. 1991.
