`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Target device : Xilinx Spartan 3AN XC3S200AN
// Author : Jordan Penard 
//
// Design name : top
//
//////////////////////////////////////////////////////////////////////////////////

`define LCD_WIDTH 640
`define H_BLANKING 160

`define LCD_HIGHT 480
`define V_BLANKING 45

`define ADDR_WIDTH 23
`define DATA_WIDTH 16

// ROM_PIPELINE is hard coded to 1 as the ROM contains 1 reg stage on the output
`define ROM_PIPELINE 1

// FIFO_PIPELINE defines the delay between the write and the read of the pipeline fifo
`define FIFO_PIPELINE 1

// OUTPUT_PIPELINE is hard coded to 1 final stage of reg before going to the LCD IOs
`define OUTPUT_PIPELINE 1

`define PIXEL_PIPELINE (`ROM_PIPELINE + `FIFO_PIPELINE + `OUTPUT_PIPELINE)


module top(
     input wire ref_clk,
     input wire rst,
     output wire [7:0] BANKA_io,
     output wire [7:0] BANKB_io,
     output wire [7:0] BANKC_io,
     output wire [6:0] BANKD_io,
     output wire led1,
     output wire led2,
     output wire led3,
     output wire led4,
     output wire SDRAM_CLK,
     output wire SDRAM_CKE,
     output wire SDRAM_CSB,
     output wire SDRAM_CASB,
     output wire SDRAM_RASB,
     output wire SDRAM_WEB,
     output wire [1:0] SDRAM_BA,
     output wire SDRAM_LDQM,
     output wire SDRAM_UDQM,
     output wire [11:0] SDRAM_ADDR,
     inout wire [15:0] SDRAM_DQ     
    );

    // ref_clk : 48Mhz
    // sys_clk/SDRAM_CLK : 96Mhz
    // pixel_clk : 24Mhz (LCD refresh = ~60Hz)
    
    wire sys_clk;
    wire pixel_clk;

    assign SDRAM_CLK = sys_clk;
    
    // -------------------- //
    // CLK dividers

    dcm_sdram_clk i_dcm_sdram_clk (
         .CLKIN_IN(ref_clk), 
         .RST_IN(rst), 
         .CLK2X_OUT(sys_clk)
         );
         
    dcm_pixel_clk i_dcm_pixel_clk (
         .CLKIN_IN(ref_clk), 
         .RST_IN(rst), 
         .CLK0_OUT(), 
         .CLKDV_OUT(pixel_clk)
         );

    // -------------------- //
    // SDRAM controller
    
    reg [7:0] cnt;
    reg error;
    
    reg [3:0] state;
    reg [1:0] cmd;
    reg [`ADDR_WIDTH-1:0] addr;
    reg [`DATA_WIDTH-1:0] wr_data;

    reg [3:0] state_next;
    reg [1:0] cmd_next;    
    reg [`ADDR_WIDTH-1:0] addr_next;
    reg [`DATA_WIDTH-1:0] wr_data_next;

    wire wr_enable;
    wire rd_enable;
    assign {wr_enable,rd_enable} = cmd;

    wire [`DATA_WIDTH-1:0] rd_data;
    wire rd_ready;
    wire busy;
        
    assign led1 = !error;
    assign led2 = 1'b1;
    assign led3 = !busy;
    assign led4 = busy;
    
    sdram_controller #(
        .HADDR_WIDTH(`ADDR_WIDTH),
        .HDATA_WIDTH(`DATA_WIDTH),
        .COL_WIDTH(9),
        .ROW_WIDTH(12),
        .BANK_WIDTH(2),
        .CLK_FREQUENCY(48), // Mhz
        .REFRESH_TIME(64),  // ms     (how often we need to refresh)
        .REFRESH_COUNT(4096)// cycles (how many refreshes required per refresh time)
    ) i_sdram_controller (
        .wr_addr(addr),
        .wr_data(wr_data),
        .wr_enable(wr_enable),
        .rd_addr(addr),
        .rd_data(rd_data),
        .rd_ready(rd_ready),
        .rd_enable(rd_enable),
        .busy(busy),
        .rst_n(!rst),
        .clk(sys_clk),
        .addr(SDRAM_ADDR),
        .bank_addr(SDRAM_BA),
        .data(SDRAM_DQ),
        .clock_enable(SDRAM_CKE),
        .cs_n(SDRAM_CSB),
        .ras_n(SDRAM_RASB),
        .cas_n(SDRAM_CASB),
        .we_n(SDRAM_WEB),
        .data_mask_low(SDRAM_LDQM),
        .data_mask_high(SDRAM_UDQM)
    );
    
    // -------------------- //
    // Main system FSM

    // State
    localparam  INIT        = 4'b0000,
                WR_REQUEST  = 4'b0001,
                WR_RESPONSE = 4'b0010,
                WAIT        = 4'b0011,
                RD_REQUEST  = 4'b0100,
                RD_RESPONSE = 4'b0101,
                RD_VALID    = 4'b0110;

    // Cmd
    localparam  NOP   = 2'b00,
                READ  = 2'b01,
                WRITE = 2'b10;

    always @ (posedge sys_clk or posedge rst)
    begin
        if (rst) begin
            state <= INIT;
            cmd <= NOP;
            addr <= 'b0;
            wr_data <= 'b0;
            error <= 'b0;
            cnt <= 'b0;
        end
        else begin
            state <= state_next;
            cmd <= cmd_next;
            addr <= addr_next;
            wr_data <= wr_data_next;

            if (state == INIT || state == WAIT)
                cnt <= cnt + 1;
            else
                cnt <= 'b0;
            
            if (state == RD_VALID) begin
                if (rd_data != 16'hFF00)
                    error <= 'b1;
            end
        end
    end
    
    always @* begin
        state_next = state;
        cmd_next = cmd;
        addr_next = addr;
        wr_data_next = wr_data;
        
        case (state)
            INIT: begin
                if (cnt == {8{1'b1}}) begin
                    state_next = WR_REQUEST;
                    cmd_next = WRITE;
                    wr_data_next = 16'hFF00;
                end
            end
        
            WR_REQUEST: begin
                if (busy) begin
                    state_next = WR_RESPONSE;
                    cmd_next = NOP;
                end
            end

            WR_RESPONSE: begin
                if (!busy) begin
                    state_next = WAIT;
                    cmd_next = NOP;
                end
            end

            WAIT: begin
                if (cnt == {8{1'b1}}) begin
                    state_next = RD_REQUEST;
                    cmd_next = READ;
                end
            end

            RD_REQUEST: begin
                if (busy) begin
                    state_next = RD_RESPONSE;
                    cmd_next = NOP;
                end
            end

            RD_RESPONSE: begin
                if (rd_ready) begin
                    state_next = RD_VALID;
                    cmd_next = NOP;
                end
            end
        
            RD_VALID: begin
                state_next = WR_REQUEST;
                cmd_next = WRITE;
                addr_next = addr + 1;
            end
        endcase
    end
    
    // -------------------- //
    // LCD control signals

    reg [7:0] pixel_blanking_cnt;
    reg [9:0] pixel_cnt;
    reg [9:0] row_cnt;
    wire h_blanking = pixel_blanking_cnt < (`H_BLANKING - 1);
    wire v_blanking = row_cnt >= `LCD_HIGHT;
    wire blanking = h_blanking || v_blanking;
    
    always @ (posedge pixel_clk or posedge rst)
    begin
        if (rst) begin
            pixel_blanking_cnt <= 'b0;
            pixel_cnt <= 'b0;
            row_cnt <= 'b0;
        end
        else begin
            if (h_blanking)
                pixel_blanking_cnt <= pixel_blanking_cnt + 1;
            else if (pixel_cnt == (`LCD_WIDTH - 1)) begin
                pixel_cnt <= 'b0;
                pixel_blanking_cnt <= 'b0;
                if (row_cnt == (`LCD_HIGHT + `V_BLANKING)-1) 
                    row_cnt <= 'b0;
                else 
                    row_cnt <= row_cnt + 1;
            end
            else
                pixel_cnt <= pixel_cnt + 1;
        end
    end

    // -------------------- //
    // Pixel control pileline
    
    reg [7:0] pixel_blanking_cnt_1[`PIXEL_PIPELINE-1:0];
    reg [9:0] pixel_cnt_1[`PIXEL_PIPELINE-1:0];
    reg [9:0] row_cnt_1[`PIXEL_PIPELINE-1:0];
    reg [`PIXEL_PIPELINE-1:0] blanking_1;
    genvar g0;

    always @ (posedge pixel_clk or posedge rst)
    begin
        if (rst) begin
            pixel_blanking_cnt_1[0] <= 'b0;
            pixel_cnt_1[0] <= 'b0;
            row_cnt_1[0] <= 'b0;
            blanking_1[0] <= 'b0;
        end
        else begin
            pixel_blanking_cnt_1[0] <= pixel_blanking_cnt;
            pixel_cnt_1[0] <= pixel_cnt;
            row_cnt_1[0] <= row_cnt;
            blanking_1[0] <= blanking;
        end
    end
    
    generate
    for(g0=1 ;g0<`PIXEL_PIPELINE;g0=g0+1) begin: counter_pipeline
        always @ (posedge pixel_clk or posedge rst) begin
            if (rst) begin
                pixel_blanking_cnt_1[g0] <= 'b0;
                pixel_cnt_1[g0] <= 'b0;
                row_cnt_1[g0] <= 'b0;
                blanking_1[g0] <= 'b0;
            end
            else begin
                pixel_blanking_cnt_1[g0] <= pixel_blanking_cnt_1[g0-1];
                pixel_cnt_1[g0] <= pixel_cnt_1[g0-1];
                row_cnt_1[g0] <= row_cnt_1[g0-1];
                blanking_1[g0] <= blanking_1[g0-1];
            end
        end
    end
    endgenerate
    
    // -------------------- //
    // Char graphics generation
    
    wire [7:0] char_to_print = "0" + pixel_cnt[9:3];
    wire [7:0] from_char_rom;
    
    // The ROM is 8x4096 (256 char of 8x16), built from the generated font_rom.coe, 1 stage of reg on the output
    font_rom i_font_rom (
        .a({char_to_print,row_cnt[3:0]}),
        .clk(pixel_clk),
        .qspo(from_char_rom)
    );
    // Checker board pattern bypassing the rom
    //assign from_char_rom = row_cnt[3] ? 8'hF0 : 8'h0F;
    
    // -------------------- //
    // Pixel data pileline

    wire pixel_pipeline_full;
    wire pixel_pipeline_empty;
    wire pixel_pipeline_wr_en = !blanking_1[`ROM_PIPELINE-1] && !pixel_pipeline_full;
    wire pixel_pipeline_rd_en = !blanking_1[`ROM_PIPELINE+`FIFO_PIPELINE-1] && !pixel_pipeline_empty;
    wire [23:0] pixel_pipeline_in = {24{from_char_rom[8-pixel_cnt_1[`ROM_PIPELINE-1][2:0]]}};
    wire [23:0] pixel_pipeline_out;
                
    pixel_pipeline i_pixel_pipeline (
      .clk(pixel_clk), // input clk
      .rst(rst), // input rst
      .din(pixel_pipeline_in), // input [23 : 0] din
      .wr_en(pixel_pipeline_wr_en), // input wr_en
      .rd_en(pixel_pipeline_rd_en), // input rd_en
      .dout(pixel_pipeline_out), // output [23 : 0] dout
      .full(pixel_pipeline_full), // output full
      .empty(pixel_pipeline_empty) // output empty
    );
    
    // -------------------- //
    // LCD final stage

    reg enb;
    
    // hsync = 0
    // vsync = 0
    // LEDCTRL = 1
    // PWCTRL = 1
    // LR = 0
    // UD = 1
    assign BANKD_io[6] = enb; // ENB (DE mode)
    assign BANKD_io[1] = !rst; // _RESET
    assign BANKD_io[2] = !pixel_clk;
    
    assign BANKD_io[0] = 1'b1;
    assign BANKD_io[4] = 1'b0;
    assign BANKD_io[5] = 1'b0;
    assign BANKD_io[3] = 1'b0;
    
    always @ (posedge pixel_clk or posedge rst)
    begin
        if (rst)
            enb <= 'b0;
        else
            enb <= !blanking_1[`PIXEL_PIPELINE-1];
    end

    reg [7:0] red_reg;
    reg [7:0] green_reg;
    reg [7:0] blue_reg;
    
    assign BANKA_io = red_reg;
    assign BANKB_io = green_reg;
    assign BANKC_io = blue_reg;
        
    always @ (posedge pixel_clk or posedge rst)
    begin
        if (rst) begin
            red_reg <= 8'b0;
            green_reg <= 8'b0;
            blue_reg <= 8'b0;
        end
        else begin
            red_reg <= pixel_pipeline_out[23:16];
            green_reg <= pixel_pipeline_out[15:8];
            blue_reg <= pixel_pipeline_out[7:0];

                /* 
                // Checker board pattern
                if (pixel_cnt_1[`PIXEL_PIPELINE-1][7] ^ row_cnt_1[`PIXEL_PIPELINE-1][7]) begin
                    red_reg <= 8'hFF;
                    green_reg <= 8'hFF;
                    blue_reg <= 8'hFF;
                end
                else begin
                    red_reg <= 8'h0;
                    green_reg <= 8'h0;
                    blue_reg <= 8'h0;
                end
                */
                /*
                // Color range pattern
                if (row_cnt_1[`PIXEL_PIPELINE-1] < (`LCD_HIGHT/3)) begin
                    red_reg <= 255-(pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                    green_reg <= (pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                    blue_reg <= (pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                end
                else if (row_cnt_1[`PIXEL_PIPELINE-1] < ((`LCD_HIGHT*2)/3)) begin
                    red_reg <= (pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                    green_reg <= 255-(pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                    blue_reg <= (pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                end
                else begin
                    red_reg <= (pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                    green_reg <= (pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                    blue_reg <= 255-(pixel_cnt_1[`PIXEL_PIPELINE-1][7:1]<<1);
                end
                */
        end
    end


endmodule
