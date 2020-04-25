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

`define LCD_WIDTH 640
`define H_BLANKING 160

`define LCD_HIGHT 480
`define V_BLANKING 45

`define ADDR_WIDTH 23
`define DATA_WIDTH 32

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
    output wire led4
/*	 output wire SDRAM_CLK,
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
*/    );

	// ref_clk : 48Mhz
	// sys_clk : 48Mhz
	// pixel_clk : 24Mhz (LCD refresh = ~60Hz)
	
	//wire sys_clk;
	//wire sdram_clk;
	wire pixel_clk;
	//wire rom_clk;
/*
	dcm_sdram_clk i_dcm_sdram_clk (
		 .CLKIN_IN(ref_clk), 
		 .RST_IN(rst), 
		 .CLK0_OUT(sys_clk), 
		 .CLK270_OUT(SDRAM_CLK)
		 );
*/		 
	dcm_pixel_clk i_dcm_pixel_clk (
		 .CLKIN_IN(ref_clk), 
		 .RST_IN(rst), 
		 .CLK0_OUT(), 
		 .CLKDV_OUT(pixel_clk)
		 );

/*	 
	reg [`ADDR_WIDTH-1:0] addr;
	reg [`DATA_WIDTH-1:0] data;
	wire [`DATA_WIDTH-1:0] q;
	reg we = 'b0;
	reg req = 'b0;
	wire ack;
	wire valid;
	
	sdram #(
		.CLK_FREQ(48.0),
		.ADDR_WIDTH(`ADDR_WIDTH),
		.DATA_WIDTH(`DATA_WIDTH),
		.SDRAM_ADDR_WIDTH(12),
		.SDRAM_DATA_WIDTH(16),
		.SDRAM_COL_WIDTH(9),
		.SDRAM_ROW_WIDTH(12),
		.SDRAM_BANK_WIDTH(2),
		.CAS_LATENCY(2),
		.BURST_LENGTH(2),
		.T_DESL(200000.0), 	// startup delay
		.T_MRD(40.0), 			// mode register cycle time
		.T_RC(90.0), 			// row cycle time
		.T_RCD(20.0), 			// RAS to CAS delay
		.T_RP(20.0), 			// precharge to activate delay
		.T_WR(20.0), 			// write recovery time
		.T_REFI(15600.0) 		// average refresh interval
	) i_sdram_controller (
		 .reset(rst), 
		 .clk(sys_clk), 
		 .addr(addr), 
		 .data(data), 
		 .we(we), 
		 .req(req), 
		 .ack(ack), 
		 .valid(valid), 
		 .q(q), 
		 .sdram_a(SDRAM_ADDR), 
		 .sdram_ba(SDRAM_BA), 
		 .sdram_dq(SDRAM_DQ), 
		 .sdram_cke(SDRAM_CKE), 
		 .sdram_cs_n(SDRAM_CSB), 
		 .sdram_ras_n(SDRAM_RASB), 
		 .sdram_cas_n(SDRAM_CASB), 
		 .sdram_we_n(SDRAM_WEB), 
		 .sdram_dqml(SDRAM_LDQM), 
		 .sdram_dqmh(SDRAM_UDQM)
		 );*/
	 

	
	//
	/*
	reg [25:0] cnt;

	always @ (posedge sys_clk or posedge rst)
	begin
		if (rst) begin
			cnt <= 'b0;
		end
		else begin
			cnt <= cnt + 1;
		end
	end*/

	
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
	
	wire [7:0] from_char_rom;
	
	// The ROM is 8x4096 (256 char of 8x16), built from the generated font_rom.coe, fully async
	font_rom i_font_rom (
		.a((("0" + {5'b0,pixel_cnt[9:3]}) << 4) | row_cnt[3:0]),
		.clk(pixel_clk),
		.qspo(from_char_rom)
	);
	// Checker board pattern bypassing the rom
	//assign from_char_rom = row_cnt[3] ? 8'hF0 : 8'h0F;
	
	// -------------------- //
	// Pixel data pileline

	wire pixel_pipeline_full;
	wire pixel_pipeline_empty;
	wire pixel_pipeline_wr_en = !blanking_1[`ROM_PIPELINE-1] && !pixel_pipeline_full && (pixel_cnt_1[`ROM_PIPELINE-1][2:0] == 3'b000);
	wire pixel_pipeline_rd_en = !blanking_1[`ROM_PIPELINE+`FIFO_PIPELINE-1] && !pixel_pipeline_empty && (pixel_cnt_1[`ROM_PIPELINE+`FIFO_PIPELINE-1][2:0] == 3'b000);
	wire [7:0] pixel_pipeline_out;

	assign led1 = !pixel_pipeline_full;
	assign led2 = !pixel_pipeline_empty;
	assign led3 = !blanking;
	assign led4 = 1'b1;
	
	pixel_pipeline i_pixel_pipeline (
	  .clk(pixel_clk), // input clk
	  .rst(rst), // input rst
	  .din(from_char_rom), // input [7 : 0] din
	  .wr_en(pixel_pipeline_wr_en), // input wr_en
	  .rd_en(pixel_pipeline_rd_en), // input rd_en
	  .dout(pixel_pipeline_out), // output [7 : 0] dout
	  .full(pixel_pipeline_full), // output full
	  .almost_full(), // output almost_full
	  .empty(pixel_pipeline_empty), // output empty
	  .almost_empty() // output almost_empty
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
			if (blanking_1[`PIXEL_PIPELINE-1]) begin
				red_reg <= 8'h0;
				green_reg <= 8'h0;
				blue_reg <= 8'h0;
			end
			else begin
				if (pixel_pipeline_out[8-pixel_cnt_1[`PIXEL_PIPELINE-1][2:0]]) begin
					red_reg <= 8'hFF;
					green_reg <= 8'hFF;
					blue_reg <= 8'hFF;
				end
				else begin
					red_reg <= 8'h0;
					green_reg <= 8'h0;
					blue_reg <= 8'h0;
				end
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
	end


/*
	//`define N 1
	reg error;
	reg [3:0] state;
	//reg [`N-1:0] addr_swipe = 'b0;

	assign led1 = !we; // Write
	assign led2 = !error;
	assign led3 = !(state == 4'd1 | state == 4'd3); // Request
	assign led4 = !(state == 4'd2 | state == 4'd4); // Response
	
	always @ (posedge sys_clk or posedge rst)
	begin
		if (rst) begin
			addr <= 'b0;
			//addr_swipe <= 'b0;
			we <= 'b0;
			req <= 'b0;
			data <= 'b0;
			state <= 'b0;
			error <= 'b0;
		end
		else begin
			// Wait
			if (state == 4'd0) begin
				if (cnt == {26{1'b1}})
					state <= 4'd1;
			end
			// Write request
			else if (state == 4'd1) begin
				//addr <= {addr_swipe,1'b0};
				addr <= 23'h55AA55;
				we <= 1'b1;
				req <= 1'b1;
				//data <= {addr_swipe,~addr_swipe} ;
				data <= 32'h55AA55AA ;
				if (ack)
					req <= 1'b0;
					state <= 4'd2;
			end
			// Write response
			else if (state == 4'd2) begin
				//if (addr_swipe == {`N{1'b1}}) begin
					state <= 4'd3;
					//addr_swipe <= 'b0;
				//end
				//else begin
				//	state <= 4'd1;
				//	addr_swipe <= addr_swipe + 1;				
				//end
			end
			// Read request
			else if (state == 4'd3) begin
				//addr <= {addr_swipe,1'b0};
				addr <= 23'h55AA55;
				we <= 1'b0;
				req <= 1'b1;
				if (ack)
					req <= 1'b0;
					state <= 4'd4;
			end
			// Read response
			else if (state == 4'd4) begin
				if (valid) begin
					//if (q != {addr_swipe,~addr_swipe})
					if (q != 32'h55AA55AB)
						error <= 'b1;
					//if (addr_swipe == {`N{1'b1}}) begin
						state <= 4'd1;
						//addr_swipe <= 'b0;
					//end
					//else begin
					//	state <= 4'd3;
					//	addr_swipe <= addr_swipe + 1;				
					//end
				end
			end
		end
	end		*/
				


	
endmodule
