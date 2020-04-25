#!/bin/bash
#\
exec /usr/bin/tclsh $0 $*


set in $argv
set fid_in [open $in]

set out rtl/font_rom.coe
set fid_out [open $out w]

puts $fid_out "memory_initialization_radix=16;"
puts $fid_out "memory_initialization_vector="

set capture 0
set capture_cnt 0
set prev_char_code 0
set char_code ""
set char_name ""

foreach line [split [read $fid_in] \n] {
    
    if {[regexp "^STARTCHAR (.*)" $line -> char_name]} {
    } elseif {[regexp "^ENCODING (.*)" $line -> char_code]} {
        if {$char_code > 255} {
	        break
	    }
        if {$char_code != 0 && [expr $char_code - 1] != $prev_char_code} {
            for {set i [expr $prev_char_code + 1]} {$i < $char_code} {incr i} {
                for {set j 0} {$j < 16} {incr j} {
                    puts $fid_out "00,"
                } 
            }
        }
    } elseif {[regexp "^ENDCHAR" $line]} {
        set capture 0
        set prev_char_code $char_code
    } elseif {[regexp "^BITMAP" $line]} {
        set capture 1
        set capture_cnt 0
    } elseif {$capture} {
        puts $fid_out "${line},"
        incr capture_cnt
    }    

}

puts $fid_out "00;"

close $fid_in
close $fid_out
