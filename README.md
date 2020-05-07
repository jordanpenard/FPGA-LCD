# FPGA-LCD

The plan is to learn about a few different things by driving an LCD from an 
FPGA using SDRAM as frame buffer.

To display text on the screen, I created a ROM for the graphics of the characters.

## Hardware
- Prototype board : Aessent aes220 (https://www.aessent.com/products/aes220-high-speed-usb-fpga-mini-module)
- FPGA : XC3S200AN
- 640x480 LCD : ET057010DMU
- 128Mb SDRAM (16 bits, 4 banks, 2M) : M52D128168A

## Generate the font ROM
```
wget http://www.inp.nsk.su./~bolkhov/files/fonts/univga/uni-vga.tgz
tar -xzf uni-vga.tgz
./bdf2coe.tcl uni_vga/u_vga16.bdf
```

## SDRAM controller
The SDRAM controller is very simple, fixed to a parameterised burst size for 
all read and write transactions, no fancy interrupt nor parallelisation, just 
a very simple controller. The size of row, column, data buses can also 
be configured via parameters. A few timing parameters are also parameterised. 

I started from the code here : https://github.com/stffrdhrn/sdram-controller



