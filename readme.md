# LFSR CPU running Forth

* Author: Richard James Howe
* License: 0BSD / Public Domain
* Email: <mailto:howe.r.j.89@gmail.com>
* Repo: <https://github.com/howerj/lfsr-vhdl>

**THIS PROJECT IS A WORK IN PROGRESS**.

This project contains a CPU written in VHDL for an FPGA using a Linear Feedback Shift 
Register (LFSR) instead of a Program Counter, this was sometimes done to save space as 
a LFSR requires fewer gates than an adder. 

See <https://github.com/howerj/lfsr> for more information. 

The project currently works in simulation (it outputs the startup message
"eForth 3.3" with a new line) and accepts input (try typing "words" when the
simulation in GHDL is running).

