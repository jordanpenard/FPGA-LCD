# FPGA-LCD

The plan is to learn about a few different things by driving an LCD from an FPGA using SDRAM as frame buffer.

## Dependancies
- SDRAM controller : https://github.com/nullobject/sdram-fpga

## Hardware
- Prototype board : Aessent aes220 (https://www.aessent.com/products/aes220-high-speed-usb-fpga-mini-module)
- FPGA : XC3S200AN
- 640x480 LCD : ET057010DMU
- 128Mb SDRAM (16 bits, 4 banks, 2M) : M52D128168A

## Font
wget http://www.inp.nsk.su./~bolkhov/files/fonts/univga/uni-vga.tgz
tar -xzf uni-vga.tgz
./bdf2coe.tcl uni_vga/u_vga16.bdf
