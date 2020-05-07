`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Testbench
// Author : Jordan Penard 
//
// Design name : tb
//
//////////////////////////////////////////////////////////////////////////////////
module tb();
    
    reg ref_clk;
    reg rst;

 	initial begin
        rst = 1'b1;
        ref_clk = 1'b0;
        #100 rst = 1'b0;
    end
    
    always 
        #10 ref_clk = !ref_clk;
 
    top i_top(
     .ref_clk(ref_clk),
     .rst(rst)   
    );


endmodule
