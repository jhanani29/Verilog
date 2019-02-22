`timescale 1ns/100ps

module alu_tb ();
   `include "functions.h"
   `include "logic_params.h"
   `include "cpu_params_RV.h"

   logic    reset;
   logic    clk_100;
   logic    [PC_SZ-1:0] pc;
   logic    [7:0] cnt;
   logic    xfer;

   //------------------------------------------------------------------------------------------------
   // Feed RISC-V instructions from program_memory to decode stage
   //------------------------------------------------------------------------------------------------
   Fetch_Data  dec_data_in;      // MUST contain both instruction and program counter value
   logic       dec_valid_in;
   logic       dec_rdy_out;

   localparam MAX_INSTR = 10; // Program Memory length - determined by number of instructions in file CPU_CODE (see cpu_params.h)
   logic    [I_SZ-1:0] program_memory [0:MAX_INSTR-1];

`define DelayClockCycles(a) \
   repeat (a) @(posedge clk_100)
   
   assign xfer = dec_valid_in & dec_rdy_out;
   
   initial
   begin
      reset    = 1'b1;
      cnt = MAX_INSTR;
      pc  = 0;
      dec_valid_in = FALSE;
      
      `DelayClockCycles(50);
      reset    = 1'b0;
      $display("Reset completed, Simulation started.");
      
      dec_valid_in = TRUE;
      
      dec_data_in.ipd[0] = '{program_memory[0],pc};
      do
      begin
         @(negedge clk_100);
         if (xfer)
         begin
            @(posedge clk_100);
            pc = pc + 1;
            dec_data_in.ipd[0] = '{program_memory[pc],pc};
            cnt = cnt - 1;
         end
      end
      while (cnt != 0);
      // you may want to put the test code to check the ALU Functional Unit output data here or at the bottom of this file... TBD by user
      dec_valid_in = FALSE;
      
      `DelayClockCycles(10);
      
      $display("Simulation completed.");
      $finish;
   end   
   

   ////////////////////////////////////////////////////////////////////////////
	// Generate 100 Mhz clock
   
	initial
	begin
		clk_100 = 1'b0;
		#44 // simulate some startup delay
		forever
			clk_100 = #5 ~clk_100;
	end
   
   //------------------------------------------------------------------------------------------------
   // Read RISC-V instructions from a file
   //------------------------------------------------------------------------------------------------
   // Xlinx allows this for ROM type initializatoin of FPGA - normally this is not synthesizable
   initial
      $readmemh(CPU_CODE, program_memory);
   
   
   //------------------------------------------------------------------------------------------------
   // Disassemble each instruction (for viewing in ModelSim) that is fed to the Decode stage
   //------------------------------------------------------------------------------------------------
   `ifdef SIM_DEBUG
   string      i_str;
   string      pc_str;
   
   disasm fdis (ASSEMBLY,dec_data_in.ipd[0],i_str,pc_str);  // disassemble each instruction to the DECODE stage
   `endif
   
   
   //------------------------------------------------------------------------------------------------
   // Decode & Micro Op stages
   //------------------------------------------------------------------------------------------------
   
   logic          dm_rdy;
   logic          dm_valid;
   Decode_Data    dm_data;
   
   MDC_Tag_Data [IPC_NUM-1:0] mdc_data;
   logic        [IPC_NUM-1:0] mdc_valid;
   logic        [IPC_NUM-1:0] mdc_rdy;
   assign dm_rdy = TRUE;
  //--------------------------------------------------------------------------------------------------
  //ALU_Functionl_Unit
  //--------------------------------------------------------------------------------------------------

   logic                      alu_valid;
   FU_Data_Out                alu_data;
   FWD_Data                   alu_fwd_data;
   FU_Data_In                 alu_data_in;
   logic                      alu_rdy_out;
   logic                      alu_rdy;
   
   Micro_Data                 md;
   Reg_Data                   rd;
   IP_Data                    ipd;
   
     
  //--------------------------------------------------------------------------------------------------
  //General Purpose Register
  //--------------------------------------------------------------------------------------------------
  
   parameter MAXP = 1;
   logic           [GPR_ASZ-1:0] Rs1_rd_reg_in [0:MAXP-1];  // Registers that can be read are Rs1[], Rs2[]
   logic           [GPR_ASZ-1:0] Rs2_rd_reg_in [0:MAXP-1];
                             
   logic               [RSZ-1:0] Rs1_rd_data_out [0:MAXP-1];  // Contents of Rs1[], Rs2[]
   logic               [RSZ-1:0] Rs2_rd_data_out [0:MAXP-1];
   logic               [RSZ-1:0] gpr_wr_data_in [0:MAX_GPR-1];
   logic           [MAX_GPR-1:0] gpr_wr_in;
     
   assign Rs1_rd_reg_in[0]   =  alu_data_in.rd.regs.Rs1;
   assign Rs2_rd_reg_in[0]   =  alu_data_in.rd.regs.Rs2;
   
   assign alu_data_in.tag = mdc_data[0].tag;
   assign alu_data_in.md  = mdc_data[0].mdcd.md;
   assign alu_data_in.rd  = mdc_data[0].mdcd.rd;
   assign alu_data_in.ipd = mdc_data[0].mdcd.ipd;
   assign alu_data_in.Rs1Data = Rs1_rd_data_out[0];
   assign alu_data_in.Rs2Data = Rs2_rd_data_out[0];
   assign alu_rdy = TRUE;
   
   integer p;
   always_comb
   begin
      for (p = 0; p < MAX_GPR; p++)
      begin
         gpr_wr_in[p]      = (p == alu_data.Rd) ? alu_data.wr_Rd : FALSE;
         gpr_wr_data_in[p] = (p == alu_data.Rd) ? alu_data.RdData : 'hdeadbeef;
//         gpr_wr_data_in[p] = alu_data.RdData;
      end
   end

   decode
      DEC (.clk_in(clk_100), .reset_in(reset),
          .data_in(dec_data_in.ipd[0]), .valid_in(dec_valid_in), .rdy_out(dec_rdy_out),
          .data_out(dm_data),    .valid_out(dm_valid),    .rdy_in(dm_rdy)
          );
 
   microcode
     MIC (  .clk_in(clk_100), .reset_in(reset),
            .data_in(dm_data), .rdy_out(dm_rdy), .valid_in(dm_valid),
            .data_out(mdc_data), .valid_out(mdc_valid), .rdy_in(alu_rdy_out)
           );
   
   alu_functional_unit
      AFU (.clk_in(clk_100), .reset_in(reset),
           .data_in(alu_data_in),  .valid_in(mdc_valid),  .rdy_out(alu_rdy_out),
           .data_out(alu_data), .valid_out(alu_valid), .rdy_in(alu_rdy),
           .fwd_data_out(alu_fwd_data)
            );	
   
  gpr 
      GRP (.clk_in(clk_100), .reset_in(reset),
           .Rs1_rd_reg_in(Rs1_rd_reg_in), .Rs2_rd_reg_in(Rs2_rd_reg_in),  
           .Rs1_rd_data_out(Rs1_rd_data_out), .Rs2_rd_data_out(Rs2_rd_data_out), 
           .gpr_wr_in(gpr_wr_in), .gpr_wr_data_in(gpr_wr_data_in)
           );

   logic wr_rd;
   int fd;
   int status;
   logic         [RSZ-1:0] RegData;
   logic     [GPR_ASZ-1:0] Reg;
   assign Reg     = alu_data_in.rd.regs.Rs1;
   assign Test    = alu_data_in.rd.regs_rw.wr_Rd;
   assign RegData = alu_data_in.Rs1Data;
   always@(Test)
   begin
    Check_Results(Reg,RegData,Test);
   end

   task Check_Results;
    input logic [GPR_ASZ-1:0] Reg;
    input logic [RSZ-1:0] RegData;
    input logic Test;
    logic wr_rd;
    int fd;
    int status; 
    logic         [RSZ-1:0] Check_RegData;
    logic     [GPR_ASZ-1:0] Check_Reg;
    if(Test == 1'b1) begin
     fd = $fopen("table.txt","r");  
     while(!($feof(fd)))
     begin
       status = $fscanf(fd,"%h,%h",Check_Reg,Check_RegData); 
       if(Check_Reg == Reg) 
        if (Check_RegData == RegData) 
          $display("The value of %h is correct",Reg);
        else begin
          $error("The value of %h with %h is not correct. It should have been %h",Reg,RegData,Check_RegData);
          #2;
          $stop;
       end
      end
     end
 endtask
endmodule
