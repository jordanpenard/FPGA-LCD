`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:43:04 04/23/2020 
// Design Name: 
// Module Name:    top 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

`define ENB_PERIOD 800
`define LCD_WIDTH 640
`define H_BLANKING (`ENB_PERIOD - `LCD_WIDTH)

`define LCD_HIGHT 480
`define V_BLANKING 45

module top(
    input wire clk,
	 input wire rst,
	 output wire [7:0] BANKA_io,
	 output wire [7:0] BANKB_io,
	 output wire [7:0] BANKC_io,
	 output wire [6:0] BANKD_io,
    output wire led1,
    output wire led2,
    output wire led3,
    output wire led4
    );

	wire pixel_clk;
	
	// Instantiate the module
	clocking i_clocking (
		 .CLKIN_IN(clk), 
		 .RST_IN(rst), 
		 .CLKDV_OUT(pixel_clk), 
		 .CLKIN_IBUFG_OUT(), 
		 .CLK0_OUT(), 
		 .LOCKED_OUT()
		 );
	 
	reg enb;
	
	reg [7:0] red_reg;
	reg [7:0] green_reg;
	reg [7:0] blue_reg;
	
	assign BANKA_io = red_reg;
	assign BANKB_io = green_reg;
	assign BANKC_io = blue_reg;
		
	assign BANKD_io[0] = pixel_clk;
	assign BANKD_io[1] = 'b0; // hsync
	assign BANKD_io[2] = 'b0; // vsync
	assign BANKD_io[3] = enb; // ENB (DE mode)
	assign BANKD_io[4] = 'b1; // LEDCTRL
	assign BANKD_io[5] = 'b1; // PWCTRL
	assign BANKD_io[6] = !rst; // _RESET

	reg [7:0] pixel_blanking_cnt;
	reg [9:0] pixel_cnt;
	reg [9:0] row_cnt;

	assign led1 = row_cnt[8];
	assign led2 = row_cnt[0];
	assign led3 = pixel_cnt[0];
	assign led4 = pixel_clk;

	always @ (posedge pixel_clk or posedge rst)
	begin
		if (rst) begin
			enb <= 'b0;
		end
		else begin
			if (pixel_cnt == 'b0 | row_cnt > `LCD_HIGHT)
				enb <= 'b0;
			else
				enb <= 'b1;
		end
	end

	always @ (posedge pixel_clk or posedge rst)
	begin
		if (rst) begin
			red_reg <= 8'b0;
			green_reg <= 8'b0;
			blue_reg <= 8'b0;
		end
		else begin
			if (row_cnt < (`LCD_HIGHT/3)) begin
				red_reg <= pixel_cnt[7:0];
				green_reg <= 8'b0;
				blue_reg <= 8'b0;
			end
			else if (row_cnt < ((`LCD_HIGHT*2)/3)) begin
				red_reg <= 8'b0;
				green_reg <= 8'hFF;
				blue_reg <= 8'b0;
			end
			else if (row_cnt < `LCD_HIGHT) begin
				red_reg <= 8'b0;
				green_reg <= 8'b0;
				blue_reg <= 8'hFF;
			end
			else begin
				red_reg <= 8'b0;
				green_reg <= 8'b0;
				blue_reg <= 8'b0;
			end
		end
	end

	always @ (posedge pixel_clk or posedge rst)
	begin
		if (rst) begin
			pixel_blanking_cnt <= 'b0;
			pixel_cnt <= 'b0;
			row_cnt <= 'b0;
		end
		else begin
			if (pixel_blanking_cnt > `H_BLANKING)
				pixel_cnt <= pixel_cnt + 1;
			else
				pixel_blanking_cnt <= pixel_blanking_cnt + 1;

			if (pixel_cnt > `LCD_WIDTH) begin
				pixel_cnt <= 'b0;
				pixel_blanking_cnt <= 'b0;
				if (row_cnt > (`LCD_HIGHT + `V_BLANKING)) 
					row_cnt <= 'b0;
				else 
					row_cnt <= row_cnt + 1;
			end
		end
	end
	
endmodule
