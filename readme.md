# LFSR CPU running Forth

* Author: Richard James Howe
* License: 0BSD / Public Domain
* Email: <mailto:howe.r.j.89@gmail.com>
* Repo: <https://github.com/howerj/lfsr-vhdl>

This project contains a CPU written in VHDL for an FPGA using a Linear Feedback Shift 
Register (LFSR) instead of a Program Counter, this was sometimes done to save space as 
a LFSR requires fewer gates than an adder, however on an FPGA it will make very
little difference as the units that make an FPGA (Slices/Configurable Logic
Blocks) have carry chains in them. The saving would perhaps be more apparent if
making the system out of 7400 series ICs, or if laying transistors out by hand. 

See <https://github.com/howerj/lfsr> for more information. 

The project currently works in simulation (it outputs the startup message
"eForth 3.3" with a new line) and accepts input (try typing "words" when the
simulation in GHDL is running).

# Building

To build you will need `make`. To make the C Virtual Machine you will need a C
compiler of your choosing.

To run the C VM type:

	make run

You should be greeted by the message `eforth 3.3`. Type `bye` and hit `ENTER`
to quit (`CTRL-D` will not work, this is not a bug). Type `words` for a list of
defined Forth words. An example session:

	: ahoy cr ." GOODBYE, CRUEL WORLD!" cr ;
	ahoy
	2 2 + . cr
	bye

This is not a Forth tutorial. For a Forth tutorial look elsewhere. Try "the
internet". I am sure they have something.

Making the simulation requires `GHDL`:

	make simulation

There is a configuration file for the simulation in the file `tb.cfg` that
allows changing many test bench parameters without recompiling the test bench.
GHDL also allows you to set generics via the command line, which is done in the
`makefile`. For example `make simulation DEBUG=2` sets the top level debug
generic to `2`, bear in mind when changing the generics in `tb.vhd` that the
`makefile` can override these constants!

To build for an FPGA you will need `Xilinx ISE 14.7`:

	make synthesis implementation bitfile

The system has not been tested on an FPGA at the moment. If you have any luck,
let me know.

# References

* <https://github.com/howerj/lfsr>
* <https://github.com/howerj/subleq>
* <https://github.com/howerj/bit-serial>
* <https://github.com/howerj/7400>
* <https://github.com/howerj/subleq-vhdl>
* <https://www.amazon.com/SUBLEQ-EFORTH-Forth-Metacompilation-Machine-ebook/dp/B0B5VZWXPL>
* <http://ghdl.free.fr/>

