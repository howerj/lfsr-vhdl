# LFSR CPU running Forth

* Author: Richard James Howe
* License: 0BSD / Public Domain
* Email: <mailto:howe.r.j.89@gmail.com>
* Repo: <https://github.com/howerj/lfsr-vhdl>

This project contains a CPU written in [VHDL][] for an [FPGA][] using a Linear Feedback Shift 
Register ([LFSR][]) instead of a Program Counter, this was sometimes done to save space as 
a [LFSR][] requires fewer gates than an adder, however on an FPGA it will make very
little difference as the units that make an FPGA (Slices/Configurable Logic
Blocks) have carry chains in them. The saving would perhaps be more apparent if
making the system out of [7400][] series ICs, or if laying transistors out by hand. 

See <https://github.com/howerj/lfsr> for more information. 

The system contains a fully working [Forth][] interpreter.

The project currently works in simulation (it outputs the startup message
"eForth 3.3" with a new line) and accepts input (try typing "words" when the
simulation in [GHDL][] is running).

# CPU Resource Utilization

The system runs can run at 151.768MHz (on a Spartan-6) according to the timing
report. The CPU itself is quite small, here is a cut-down report on the
resources consumed for commit `7dc4c9b7e03082364b09540bb2d97105d2858d0b`:

	+------------------------------------------------------------+
	| Module     | Slices | Slice Reg | LUTs  | BRAM/FIFO | BUFG | 
	+------------------------------------------------------------+
	| top/       | 3/53   | 9/105     | 1/151 | 0/8       | 1/1  | 
	| +system    | 0/27   | 0/47      | 0/85  | 0/8       | 0/0  | 
	| ++bram     | 0/0    | 0/0       | 0/0   | 8/8       | 0/0  | 
	| ++cpu      | 27/27  | 47/47     | 85/85 | 0/0       | 0/0  | 
	| +uart_rx_0 | 12/12  | 24/24     | 39/39 | 0/0       | 0/0  | 
	| +uart_tx_0 | 11/11  | 25/25     | 26/26 | 0/0       | 0/0  | 
	+------------------------------------------------------------+
	No LUTRAM/BUFIO/DSP48A1/BUFR/DCM/PLL_ADV used

The above is indicative only as the actual resources used may vary from
commit to commit, but also because of the tool chain and FPGA targeted.

Even given that though it is clear that this system is *small*. The CPU
only occupies 27 slices, which is only a little larger than the bit-serial
CPU available at <https://github.com/howerj/bit-serial>, and this 16-bit CPU
is *much* faster.

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

[GHDL]: http://ghdl.free.fr/
[FPGA]: https://en.wikipedia.org/wiki/Field-programmable_gate_array
[Forth]: https://en.wikipedia.org/wiki/Forth_(programming_language)
[make]: https://www.gnu.org/software/make/
[VHDL]: https://en.wikipedia.org/wiki/VHDL
[LFSR]: https://en.wikipedia.org/wiki/Linear-feedback_shift_register
[7400]: https://en.wikipedia.org/wiki/7400-series_integrated_circuits

