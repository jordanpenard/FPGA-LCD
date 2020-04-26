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
`define DATA_WIDTH 128

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

    reg pixel_rst;

    assign SDRAM_CLK = sys_clk;
    
    // -------------------- //
    // CLK dividers

    dcm_sys_clk i_dcm_sys_clk (
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
    reg [`ADDR_WIDTH-1:0] mem_rd_addr;
    reg [`ADDR_WIDTH-1:0] mem_wr_addr;
    reg [`DATA_WIDTH-1:0] mem_wr_data;

    reg [3:0] state_next;
    reg [1:0] cmd_next;    
    reg [`ADDR_WIDTH-1:0] mem_rd_addr_next;
    reg [`ADDR_WIDTH-1:0] mem_wr_addr_next;
    reg [`DATA_WIDTH-1:0] mem_wr_data_next;

    wire mem_wr_enable;
    wire mem_rd_enable;
    assign {mem_wr_enable,mem_rd_enable} = cmd;

    wire [`DATA_WIDTH-1:0] mem_rd_data;
    wire mem_rd_ready;
    wire mem_busy;
    
    sdram_controller #(
        .COL_WIDTH(9),
        .ROW_WIDTH(12),
        .BANK_WIDTH(2),
        .CLK_FREQUENCY(48), // Mhz
        .REFRESH_TIME(64),  // ms     (how often we need to refresh)
        .REFRESH_COUNT(4096)// cycles (how many refreshes required per refresh time)
    ) i_sdram_controller (
        .wr_addr(mem_wr_addr),
        .wr_data(mem_wr_data),
        .wr_enable(mem_wr_enable),
        .rd_addr(mem_rd_addr),
        .rd_data(mem_rd_data),
        .rd_ready(mem_rd_ready),
        .rd_enable(mem_rd_enable),
        .busy(mem_busy),
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

    wire pixel_pipeline_full;
    wire pixel_pipeline_almost_full; // Will be asserted when there is less than 256 pixel of space
                                     //  left in the fifo (aka 32 char, which is 2 burst of 128 bits)

    reg [6:0] char_gen_col_r;             // Counter for the columns relative to characters (0 to 79)
    reg [4:0] char_gen_row_r;             // Counter for the rows relative to characters (0 to 29)
    reg [2:0] char_gen_pixel_x_r;         // Counter for the horizontal pixels (0 to 639)
    reg [3:0] char_gen_pixel_y_r;         // Counter for the vertical pixels (0 to 479)
    reg char_gen_wr_enable;               // Enable for the write side of the pixel pipeline

    reg [6:0] char_gen_col_next;
    reg [4:0] char_gen_row_next;
    reg [2:0] char_gen_pixel_x_next;
    reg [3:0] char_gen_pixel_y_next;
    reg pixel_pipeline_wr_enable_next;

    // State
    localparam  INIT        = 4'b0000,
                WR_REQUEST  = 4'b0001,
                WR_RESPONSE = 4'b0010,
                WAIT        = 4'b0011,
                RD_REQUEST  = 4'b0100,
                RD_RESPONSE = 4'b0101,
                RD_VALID    = 4'b0110,
                DISPLAY     = 4'b0111;

    // Cmd
    localparam  NOP   = 2'b00,
                READ  = 2'b01,
                WRITE = 2'b10;

    assign led1 = !(state == DISPLAY);
    assign led2 = !(state == RD_REQUEST);
    assign led3 = !(state == RD_RESPONSE);
    assign led4 = !(state == WR_RESPONSE);
    
    always @ (posedge sys_clk or posedge rst)
    begin
        if (rst) begin
            state <= INIT;
            cmd <= NOP;
            mem_rd_addr <= 23'h000234;
            mem_wr_addr <= 23'h000234;
            mem_wr_data <= 'b0;
            error <= 'b0;
            cnt <= 'b0;
            char_gen_col_r <= 'b0;
            char_gen_row_r <= 'b0;
            char_gen_pixel_x_r <= 3'b111;
            char_gen_pixel_y_r <= 'b0;
        end
        else begin
            state <= state_next;
            cmd <= cmd_next;
            mem_rd_addr <= mem_rd_addr_next;
            mem_wr_addr <= mem_wr_addr_next;
            mem_wr_data <= mem_wr_data_next;
            char_gen_col_r <= char_gen_col_next;
            char_gen_row_r <= char_gen_row_next;
            char_gen_pixel_x_r <= char_gen_pixel_x_next;
            char_gen_pixel_y_r <= char_gen_pixel_y_next;

            if (state == INIT || state == WAIT)
                cnt <= cnt + 1;
            else
                cnt <= 'b0;
            
            if (state == RD_VALID) begin
                if (mem_rd_data != `DATA_WIDTH'h0123456789ABCDEF0123456789ABCDEF)
                    error <= 'b1;
            end
        end
    end
    
    always @* begin
        state_next = state;
        cmd_next = cmd;
        mem_rd_addr_next = mem_rd_addr;
        mem_wr_addr_next = mem_wr_addr;
        mem_wr_data_next = mem_wr_data;
        char_gen_col_next = char_gen_col_r;
        char_gen_row_next = char_gen_row_r;
        char_gen_pixel_x_next = char_gen_pixel_x_r;
        char_gen_pixel_y_next = char_gen_pixel_y_r;
        char_gen_wr_enable = 'b0;
        
        case (state)
            INIT: begin
                if (cnt == {8{1'b1}}) begin
                    state_next = WR_REQUEST;
                    cmd_next = WRITE;
                    mem_wr_data_next = `DATA_WIDTH'h0123456789ABCDEF0123456789ABCDEF;
                end
            end
        
            WR_REQUEST: begin
                if (mem_busy) begin
                    state_next = WR_RESPONSE;
                    cmd_next = NOP;
                end
            end

            WR_RESPONSE: begin
                if (!mem_busy) begin
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
                if (mem_busy) begin
                    state_next = RD_RESPONSE;
                    cmd_next = NOP;
                end
            end

            RD_RESPONSE: begin
                if (mem_rd_ready) begin
                    state_next = RD_VALID;
                    cmd_next = NOP;
                end
            end
        
            RD_VALID: begin
                state_next = DISPLAY;
                cmd_next = NOP;
            end
            
            DISPLAY: begin
                if (!pixel_pipeline_almost_full) begin
                    char_gen_wr_enable = 'b1;
                    // Update x and y character counters
                    if (char_gen_pixel_x_r == 3'b000) begin
                        char_gen_pixel_x_next = 3'b111;
                        if (char_gen_col_r == 79) begin
                            char_gen_col_next = 'b0;
                            if (char_gen_pixel_y_r == 4'b1111) begin
                                char_gen_pixel_y_next = 4'b0000;
                                if (char_gen_row_r == 29) begin
                                    char_gen_row_next = 'b0;
                                    state_next = INIT;
                                    cmd_next = NOP;
                                end
                                else
                                    char_gen_row_next = char_gen_row_r + 1;
                            end
                            else
                                char_gen_pixel_y_next = char_gen_pixel_y_r + 1;
                        end
                        else
                            char_gen_col_next = char_gen_col_r + 1;
                    end
                    else
                        char_gen_pixel_x_next = char_gen_pixel_x_r - 1;
                end
            end
        endcase
    end

    // -------------------- //
    // Font ROM
    
    reg [3:0] font_rom_pixel_y_r;
    reg [2:0] font_rom_pixel_x_r;
    reg font_rom_wr_en_r;

    reg [7:0] font_rom_char_to_print_r;            // ASCII code of the caracter to print
    reg [7:0] font_rom_char_to_print_next;

    wire [7:0] from_font_rom_r;

    always @ (posedge sys_clk or posedge rst)
    begin
        if (rst) begin
            font_rom_pixel_y_r <= 'b0;
            font_rom_pixel_x_r <= 'b0;
            font_rom_wr_en_r <= 'b0;
            font_rom_char_to_print_r <= " ";
        end
        else begin
            font_rom_pixel_y_r <= char_gen_pixel_y_r;
            font_rom_pixel_x_r <= char_gen_pixel_x_r;
            font_rom_wr_en_r <= char_gen_wr_enable;
            font_rom_char_to_print_r <= font_rom_char_to_print_next;
        end
    end
    
    always @* begin
        font_rom_char_to_print_next = " ";
        if (char_gen_wr_enable) begin
            // Char graphics generation
            if (char_gen_col_r == 0) begin
                case (char_gen_row_r) 
                    0: font_rom_char_to_print_next = "@";
                    1: font_rom_char_to_print_next = "W";
                    2: font_rom_char_to_print_next = "R";
                endcase
            end
            else begin
                if (char_gen_row_r == 0 && char_gen_col_r < 7)
                    font_rom_char_to_print_next = "0" + (4'hF & (mem_rd_addr >> (24 - (4*char_gen_col_r))));
                if (char_gen_row_r == 1 && char_gen_col_r < (1+(`DATA_WIDTH/4)))
                    font_rom_char_to_print_next = "0" + (4'hF & (mem_wr_data >> (`DATA_WIDTH - (4*char_gen_col_r))));
                if (char_gen_row_r == 2 && char_gen_col_r < (1+(`DATA_WIDTH/4)))
                    font_rom_char_to_print_next = "0" + (4'hF & (mem_rd_data >> (`DATA_WIDTH - (4*char_gen_col_r))));
                if (font_rom_char_to_print_next > "9" && font_rom_char_to_print_next < "A")
                    font_rom_char_to_print_next = font_rom_char_to_print_next + 7;
            end
        end
    end
    
    // The ROM is 8x4096 (256 char of 8x16), built from the generated font_rom.coe, 1 stage of reg on the output
    font_rom i_font_rom (
        .a({font_rom_char_to_print_r,font_rom_pixel_y_r}),
        .clk(sys_clk),
        .qspo_rst(rst),
        .qspo(from_font_rom_r)
    );    
    
    // -------------------- //
    // LCD control signals

    reg [7:0] lcd_blanking_cnt_r;
    reg [9:0] lcd_pixel_x_r;
    reg [9:0] lcd_pixel_y_r;
    wire lcd_h_blanking = lcd_blanking_cnt_r < (`H_BLANKING - 1);
    wire lcd_v_blanking = lcd_pixel_y_r >= `LCD_HIGHT;
    
    always @ (posedge pixel_clk or posedge pixel_rst)
    begin
        if (pixel_rst) begin
            lcd_blanking_cnt_r <= 'b0;
            lcd_pixel_x_r <= 'b0;
            lcd_pixel_y_r <= 'b0;
        end
        else begin
            if (lcd_h_blanking)
                lcd_blanking_cnt_r <= lcd_blanking_cnt_r + 1;
            else if (lcd_pixel_x_r == (`LCD_WIDTH - 1)) begin
                lcd_pixel_x_r <= 'b0;
                lcd_blanking_cnt_r <= 'b0;
                if (lcd_pixel_y_r == (`LCD_HIGHT + `V_BLANKING)-1) 
                    lcd_pixel_y_r <= 'b0;
                else 
                    lcd_pixel_y_r <= lcd_pixel_y_r + 1;
            end
            else
                lcd_pixel_x_r <= lcd_pixel_x_r + 1;
        end
    end
    
    // -------------------- //
    // Pixel data pileline

    reg [2:0] pixel_pipeline_wr_pixel_x_r;
    reg pixel_pipeline_wr_en_r;

    wire [23:0] pixel_pipeline_in = {24{from_font_rom_r[pixel_pipeline_wr_pixel_x_r]}};

    wire pixel_pipeline_empty;
    wire pixel_pipeline_rd_en = !lcd_h_blanking & !lcd_v_blanking && !pixel_pipeline_empty;
    
    wire [23:0] pixel_pipeline_out_r;

    always @ (posedge sys_clk or posedge rst)
    begin
        if (rst) begin
            pixel_pipeline_wr_pixel_x_r <= 'b0;
            pixel_pipeline_wr_en_r <= 'b0;
        end
        else begin
            pixel_pipeline_wr_pixel_x_r <= font_rom_pixel_x_r;
            pixel_pipeline_wr_en_r <= font_rom_wr_en_r;
        end
    end
    
    // Only releasing the reset of the pixel domain once the first pixel is in the pipeline
    // As write to the piepline is on a faster clock, starving the fifo shouldn't be a worry
    always @ (posedge sys_clk or posedge rst)
    begin
        if (rst)
            pixel_rst <= 'b1;
        else if (pixel_rst && !pixel_pipeline_empty)
            pixel_rst <= 'b0;
    end
    
    pixel_pipeline i_pixel_pipeline (
      .wr_clk(sys_clk), // input wr_clk
      .rd_clk(pixel_clk), // input rd_clk
      .rst(rst), // input rst
      .din(pixel_pipeline_in), // input [23 : 0] din
      .wr_en(pixel_pipeline_wr_en_r), // input wr_en
      .rd_en(pixel_pipeline_rd_en), // input rd_en
      .dout(pixel_pipeline_out_r), // output [23 : 0] dout
      .full(pixel_pipeline_full), // output full
      .empty(pixel_pipeline_empty), // output empty
      .prog_full(pixel_pipeline_almost_full) // output prog_full (threshold set to 767 for a fifo size of 1024)
    );
    
    // -------------------- //
    // LCD final stage

    reg lcd_enb_r;
    reg [7:0] lcd_red_r;
    reg [7:0] lcd_green_r;
    reg [7:0] lcd_blue_r;
    
    // hsync = 0
    // vsync = 0
    // LEDCTRL = 1
    // PWCTRL = 1
    // LR = 0
    // UD = 1
    assign BANKD_io[6] = lcd_enb_r; // ENB (DE mode)
    assign BANKD_io[1] = !pixel_rst; // _RESET
    assign BANKD_io[2] = !pixel_clk;
    assign BANKD_io[0] = 1'b1;
    assign BANKD_io[4] = 1'b0;
    assign BANKD_io[5] = 1'b0;
    assign BANKD_io[3] = 1'b0;
    assign BANKA_io = lcd_red_r;
    assign BANKB_io = lcd_green_r;
    assign BANKC_io = lcd_blue_r;
        
    always @ (posedge pixel_clk or posedge pixel_rst)
    begin
        if (pixel_rst) begin
            lcd_enb_r <= 'b0;
            lcd_red_r <= 'b0;
            lcd_green_r <= 'b0;
            lcd_blue_r <= 'b0;
        end
        else begin
            lcd_enb_r <= !lcd_h_blanking & !lcd_v_blanking;
            lcd_red_r <= pixel_pipeline_out_r[23:16];
            lcd_green_r <= pixel_pipeline_out_r[15:8];
            lcd_blue_r <= pixel_pipeline_out_r[7:0];
        end
    end

endmodule
