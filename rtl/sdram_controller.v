`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Target device : Xilinx Spartan 3AN XC3S200AN
// Author : Jordan Penard
// Design name : sdram_controller
// Comments :   Simple controller for M52D128168A-10BG SDRAM (2M x 16 Bit x 4 Banks)
//              Working on making it a bit more generic via parameters
//
//              Very simple host interface
//                 * wr_data - data for writing, latched in when wr_enable is high
//                 * rd_data - data for reading, comes available when rd_ready is high
//                 * rst_n - active low reset, starts the init ram process when released
//                 * rd_enable - active high read request
//                 * wr_enable - active high write request
//                 * busy - active when a read or a write is in progress, address, data
//                          and rd/wr enable inputs should be released as soon as busy is high 
//
//
//////////////////////////////////////////////////////////////////////////////////

module sdram_controller (
    /* HOST INTERFACE */
    wr_addr,
    wr_data,
    wr_enable,

    rd_addr,
    rd_data,
    rd_ready,
    rd_enable,

    busy, rst_n, clk,

    /* SDRAM SIDE */
    addr, bank_addr, data, clock_enable, cs_n, ras_n, cas_n, we_n,
    data_mask_low, data_mask_high
);

/* Parameters for SDRAM */
parameter ROW_WIDTH = 12;
parameter COL_WIDTH = 9;
parameter CLK_FREQUENCY = 96;   // Mhz
parameter REFRESH_TIME =  64;   // ms     (Tref : Refresh period, how often we need to refresh)
parameter REFRESH_COUNT = 1;    // cycles (how many refreshes required per refresh time)
parameter ROW_CYCLE_TIME = 80;  // ns     (Trfc : Row cycle time, the time it takes to auto refresh)
parameter POWERUP_TIME = 200;   // us     (How long we should wait after power up before we do any init)
parameter CAS_LATENCY = 3;      // CAS latency can either be 2 or 3
parameter BURST_LENGTH = 4;     // Burst length can be 1, 2, 4 or 8

localparam BANK_WIDTH = 2;
localparam CAS_LATENCY_INT = (CAS_LATENCY == 2) ? 3'b010 : 3'b011;

/* Parameters for Host interface */
localparam HADDR_WIDTH = BANK_WIDTH + ROW_WIDTH + COL_WIDTH;
localparam HDATA_WIDTH = 16*BURST_LENGTH;

/* Internal Parameters */
localparam SDRADDR_WIDTH = ROW_WIDTH > COL_WIDTH ? ROW_WIDTH : COL_WIDTH;

// clk / refresh =  clk / sec
//                , sec / refbatch
//                , ref / refbatch
localparam CYCLES_BETWEEN_REFRESH = ( CLK_FREQUENCY
                                      * 1_000
                                      * REFRESH_TIME
                                    ) / REFRESH_COUNT;

// 0 : Sequential Counting
// 1 : Interleave Counting
localparam BURST_COUNTING = 1'b0;

// Auto precharge during read/write
localparam AUTO_PRECHARGE = 1'b1;

// STATES - State
localparam IDLE      = 5'b00000;

localparam INIT_NOP1 = 5'b01000,
           INIT_PRE1 = 5'b01001,
           INIT_NOP1_1=5'b00101,
           INIT_REF1 = 5'b01010,
           INIT_NOP2 = 5'b01011,
           INIT_REF2 = 5'b01100,
           INIT_NOP3 = 5'b01101,
           INIT_LOAD = 5'b01110,
           INIT_NOP4 = 5'b01111;

localparam REF_PRE  =  5'b00001,
           REF_NOP1 =  5'b00010,
           REF_REF  =  5'b00011,
           REF_NOP2 =  5'b00100;

localparam READ_ACT  = 5'b10000,
           READ_NOP1 = 5'b10001,
           READ_CAS  = 5'b10010,
           READ_NOP2 = 5'b10011,
           READ_READ = 5'b10100;

localparam WRIT_ACT  = 5'b11000,
           WRIT_NOP1 = 5'b11001,
           WRIT_CAS  = 5'b11010,
           WRIT_BURST= 5'b11011,
           WRIT_NOP2 = 5'b00110;

// Commands              CCRCWBBA
//                       ESSSE100
localparam CMD_PALL = 8'b10010001,
           CMD_REF  = 8'b10001000,
           CMD_NOP  = 8'b10111000,
           CMD_MRS  = 8'b1000000x,
           CMD_BACT = 8'b10011xxx,
           CMD_READ = 8'b10101xx1,
           CMD_WRIT = 8'b10100xx1;

/* Interface Definition */
/* HOST INTERFACE */
input  [HADDR_WIDTH-1:0]   wr_addr;
input  [HDATA_WIDTH-1:0]   wr_data;
input                      wr_enable;

input  [HADDR_WIDTH-1:0]   rd_addr;
output [HDATA_WIDTH-1:0]   rd_data;
input                      rd_enable;
output                     rd_ready;

output                     busy;
input                      rst_n;
input                      clk;

/* SDRAM SIDE */
output [SDRADDR_WIDTH-1:0] addr;
output [BANK_WIDTH-1:0]    bank_addr;
inout  [15:0]              data;
output                     clock_enable;
output                     cs_n;
output                     ras_n;
output                     cas_n;
output                     we_n;
output                     data_mask_low;
output                     data_mask_high;

/* I/O Registers */

reg  [HADDR_WIDTH-1:0]   haddr_r;
reg  [HDATA_WIDTH-1:0]              wr_data_r;
reg  [HDATA_WIDTH-1:0]              rd_data_r;
reg                      busy;
reg                      data_mask_low_r;
reg                      data_mask_high_r;
reg [SDRADDR_WIDTH-1:0]  addr_r;
reg [BANK_WIDTH-1:0]     bank_addr_r;
reg                      rd_ready_r;

wire                     data_mask_low, data_mask_high;

assign data_mask_high = data_mask_high_r;
assign data_mask_low  = data_mask_low_r;
assign rd_data        = rd_data_r;

/* Internal Wiring */
reg [15:0] state_cnt;
reg [23:0] refresh_cnt;

reg [7:0] command;
reg [4:0] state;

// TODO output addr[6:4] when programming mode register

reg [7:0] command_nxt;
reg [15:0] state_cnt_nxt;
reg [4:0] next;

assign {clock_enable, cs_n, ras_n, cas_n, we_n} = command[7:3];
// state[4] will be set if mode is read/write
assign bank_addr      = (state[4]) ? bank_addr_r : command[2:1];
assign addr           = (state[4] | state == INIT_LOAD) ? addr_r : { {SDRADDR_WIDTH-11{1'b0}}, command[0], 10'd0 };

assign data = (state == WRIT_CAS || state == WRIT_BURST) ? wr_data_r[15:0] : 16'bz;
assign rd_ready = rd_ready_r;

// HOST INTERFACE
// all registered on posedge
always @ (posedge clk, negedge rst_n)
  if (~rst_n)
    begin
    state <= INIT_NOP1;
    command <= CMD_NOP;
    state_cnt <= (POWERUP_TIME * CLK_FREQUENCY);

    haddr_r <= {HADDR_WIDTH{1'b0}};
    wr_data_r <= {HDATA_WIDTH{1'b0}};
    rd_data_r <= {HDATA_WIDTH{1'b0}};
    busy <= 1'b0;
    end
  else
    begin

    state <= next;
    command <= command_nxt;

    if (!state_cnt)
      state_cnt <= state_cnt_nxt;
    else
      state_cnt <= state_cnt - 1'b1;

    if (state == WRIT_CAS || state == WRIT_BURST)
      wr_data_r <= (wr_data_r >> 16);
      
    if (state == WRIT_ACT)
      wr_data_r <= wr_data;
    
    if (state == READ_ACT)
      rd_data_r <= {HDATA_WIDTH{1'b0}};

    if (state == READ_READ)
      begin
      rd_data_r <= {data,rd_data_r} >> 16;
      if (!state_cnt)
        rd_ready_r <= 1'b1;
      end
    else begin
      rd_ready_r <= 1'b0;
    end

    busy <= state[4];

    if (rd_enable)
      haddr_r <= rd_addr;
    else if (wr_enable)
      haddr_r <= wr_addr;

    end

// Handle refresh counter
always @ (posedge clk, negedge rst_n)
 if (~rst_n)
   refresh_cnt <= 10'b0;
 else
   if (state == REF_NOP2)
     refresh_cnt <= 10'b0;
   else
     refresh_cnt <= refresh_cnt + 1'b1;


/* Handle logic for sending addresses to SDRAM based on current state*/
always @*
begin
    if (state == WRIT_CAS || state == WRIT_BURST || state == READ_CAS || state == READ_NOP2 || state == READ_READ)
      {data_mask_low_r, data_mask_high_r} = 2'b00;
    else
      {data_mask_low_r, data_mask_high_r} = 2'b11;

   bank_addr_r = 2'b00;
   addr_r = {SDRADDR_WIDTH{1'b0}};

   if (state == READ_ACT || state == WRIT_ACT)
     begin
     bank_addr_r = haddr_r[HADDR_WIDTH-1:HADDR_WIDTH-(BANK_WIDTH)];
     addr_r = haddr_r[HADDR_WIDTH-(BANK_WIDTH+1):HADDR_WIDTH-(BANK_WIDTH+ROW_WIDTH)];
     end
   else if (state == READ_CAS || state == WRIT_CAS)
     begin
     // Send Column Address
     // Set bank to bank to precharge
     bank_addr_r = haddr_r[HADDR_WIDTH-1:HADDR_WIDTH-(BANK_WIDTH)];

     // Examples for math
     //               BANK  ROW    COL
     // HADDR_WIDTH   2 +   13 +   9   = 24
     // SDRADDR_WIDTH 13

     // Set CAS address to:
     //   0s,
     //   1 (A10 is always for auto precharge),
     //   0s,
     //   column address
     addr_r = {
               {SDRADDR_WIDTH-(11){1'b0}},
               AUTO_PRECHARGE,            /* A10 */
               {10-COL_WIDTH{1'b0}},
               haddr_r[COL_WIDTH-1:0]
              };
     end
   else if (state == INIT_LOAD)
     begin
     // Program mode register during load cycle
     //                                       B  C  SB
     //                                       R  A  EUR
     //                                       S  S-3Q ST
     //                                       T  654L210
     addr_r = {{SDRADDR_WIDTH-10{1'b0}}, 3'b000,
        CAS_LATENCY_INT,
        BURST_COUNTING,
        (BURST_LENGTH==1)?3'b000:
        ((BURST_LENGTH==2)?3'b001:
        ((BURST_LENGTH==4)?3'b010:
        ((BURST_LENGTH==8)?3'b011:3'b000)))};
     end
end

// Next state logic
always @*
begin
   state_cnt_nxt = 4'd0;
   command_nxt = CMD_NOP;
   if (state == IDLE)
        // Monitor for refresh or hold
        if (refresh_cnt >= CYCLES_BETWEEN_REFRESH)
          begin
          next = REF_PRE;
          command_nxt = CMD_PALL;
          end
        else if (rd_enable)
          begin
          next = READ_ACT;
          command_nxt = CMD_BACT;
          end
        else if (wr_enable)
          begin
          next = WRIT_ACT;
          command_nxt = CMD_BACT;
          end
        else
          begin
          // HOLD
          next = IDLE;
          end
    else
      if (!state_cnt)
        case (state)
          // INIT ENGINE
          INIT_NOP1:
            begin
            next = INIT_PRE1;
            command_nxt = CMD_PALL;
            end
          INIT_PRE1:
            begin
            next = INIT_NOP1_1;
            end
          INIT_NOP1_1:
            begin
            next = INIT_REF1;
            command_nxt = CMD_REF;
            end
          INIT_REF1:
            begin
            next = INIT_NOP2;
            state_cnt_nxt = ((ROW_CYCLE_TIME * CLK_FREQUENCY) / 1_000) - 1;
            end
          INIT_NOP2:
            begin
            next = INIT_REF2;
            command_nxt = CMD_REF;
            end
          INIT_REF2:
            begin
            next = INIT_NOP3;
            state_cnt_nxt = ((ROW_CYCLE_TIME * CLK_FREQUENCY) / 1_000) - 1;
            end
          INIT_NOP3:
            begin
            next = INIT_LOAD;
            command_nxt = CMD_MRS;
            end
          INIT_LOAD:
            begin
            next = INIT_NOP4;
            state_cnt_nxt = 4'd1;
            end
          // INIT_NOP4: default - IDLE

          // REFRESH
          REF_PRE:
            begin
            next = REF_NOP1;
            end
          REF_NOP1:
            begin
            next = REF_REF;
            command_nxt = CMD_REF;
            end
          REF_REF:
            begin
            next = REF_NOP2;
            state_cnt_nxt = ((ROW_CYCLE_TIME * CLK_FREQUENCY) / 1_000) - 1;
            end
          // REF_NOP2: default - IDLE

          // WRITE
          WRIT_ACT:
            begin
            next = WRIT_NOP1;
            state_cnt_nxt = 4'd1;
            end
          WRIT_NOP1:
            begin
            next = WRIT_CAS;
            command_nxt = CMD_WRIT;
            end
          WRIT_CAS:
            begin
                if (BURST_LENGTH > 1) begin
                    next = WRIT_BURST;
                    state_cnt_nxt = BURST_LENGTH-2;
                end
                else begin
                    next = WRIT_NOP2;
                    state_cnt_nxt = 1;
                end
            end
          WRIT_BURST:
            begin
            next = WRIT_NOP2;
            state_cnt_nxt = 1; // We need 2 cycles of inactivity at the end of the write
            end
          // WRIT_NOP2: default - IDLE

          // READ
          READ_ACT:
            begin
            next = READ_NOP1;
            state_cnt_nxt = 4'd1;
            end
          READ_NOP1:
            begin
            next = READ_CAS;
            command_nxt = CMD_READ;
            end
          READ_CAS:
            begin
            next = READ_NOP2;
            state_cnt_nxt = CAS_LATENCY_INT - 2;
            end
          READ_NOP2:
            begin
            next = READ_READ;
            state_cnt_nxt = BURST_LENGTH-1;
            end
          // READ_READ: default - IDLE

          default:
            begin
            next = IDLE;
            end
          endcase
      else
        begin
        // Counter Not Reached - HOLD
        next = state;
        command_nxt = command;
        end
end

endmodule
