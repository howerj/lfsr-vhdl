-- File:        lfsr.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/lfsr-vhdl
-- License:     0BSD / Public Domain
-- Description: 16-bit Accumulator CPU with LFSR as PC
--
-- This file contains a configurable CPU core that uses a Linear Feedback
-- Shift Register (LFSR) as a Program Counter (PC) instead of a normal adder to 
-- advance to the next state. Historically this was very rarely used to save on 
-- the number of gates used to implement a PC as a LFSR requires fewer gate than
-- an adder. It is actually possible to use an adder, selectable via a generic,
-- instead if you so wish.
--
-- Although this CPU is quite odd, it is capable of running a full blown
-- programming language called Forth. The image to do this should be part of
-- the project, but you will not find any "Forth" in this file. The tool-chain
-- to build the image is available at <https://github.com/howerj/lfsr>.
--
-- In the default configuration this 16-bit Accumulator CPU only has an
-- 8-bit Program Counter, which means it can only address 256 16-bit values.
-- This is enough to implement a Virtual Machine which can address the full
-- range a 16-bit value allows (65536 cells).
--
-- The CPU is a proof-of-concept, although when laying gates out by hand
-- there is a saving in numbers of gates (and also a potential speed boost
-- compared to a normal adder) due to the way the primitives on an FPGA are
-- implemented there is most likely no saving at all (the building blocks,
-- Slices and Configurable Logic Blocks on Xilinx devices) contain logic
-- to help implement the carry logic needed by an adder efficiently.
--
-- The CPU starts executing at address 0, which is a special value for a
-- XOR based LFSR in that it is a lockup state from which there is no escape.
-- This can be addressed by having the first instruction as a JUMP.
--
-- There are 8 instructions; XOR, AND, Left Shift by 1, Right Shift by 1,
-- Load, Store, Jump and Jump-on-Zero. Each instruction has a 12-bit operand,
-- and if the high bit is set that operand is loaded from memory instead of
-- being used directly by the instruction (thus turning a load into an indirect
-- load, a jump into an indirect jump, or loading a full 16-bit value to be
-- AND'ed with the accumulator).
--
-- There are no interrupts.
--
-- If you find a use for this CPU, please let me know, it has been made just
-- for fun and I doubt it has practical applications.
--
-- The code for making a LFSR could go in its own module, we could also make
-- it was we can generate XNOR variants as well.
--

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- Used for debug only (turned off for synthesis)

entity lfsr is
	generic (
		asynchronous_reset: boolean    := true;   -- use asynchronous reset if true, synchronous if false
		delay:              time       := 0 ns;   -- simulation only, gate delay
		N:                  positive   := 16;     -- size the CPU
		pc_length:          positive   := 8;      -- size of the LFSR polynomial
		jspec:              std_ulogic_vector(4 downto 0) := "00111"; -- Jump specification
		polynomial:         std_ulogic_vector(15 downto 0) := x"00B8"; -- LFSR polynomial to use
		non_blocking_input: boolean    := false;  -- if true, input will be -1 if there is no input
		pc_is_lfsr:         boolean    := true;   -- switch between using a counter and using a LFSR
		halt_enable:        boolean    := false;  -- a jump to self causes `halted` to be raised
		multiple_io:        boolean    := false;  -- enable address output on I/O states
		replace_lsl1:       boolean    := false;  -- replace LSR1 instruction with add
		debug:              natural    := 0);     -- debug level, 0 = off
	port (
		clk:           in std_ulogic; -- Guess what this is?
		rst:           in std_ulogic; -- Can be sync or async
		o:            out std_ulogic_vector(N - 1 downto 0); -- Memory access; Output
		i:             in std_ulogic_vector(N - 1 downto 0); -- Memory access; Input
		a:            out std_ulogic_vector(N - 1 downto 0); -- Memory access; Address
		we, re:       out std_ulogic; -- Write and read enable for memory only
		obyte:        out std_ulogic_vector(7 downto 0); -- Output byte
		ibyte:         in std_ulogic_vector(7 downto 0); -- Input byte
		obsy, ihav:    in std_ulogic; -- Output busy / Have input
		io_we, io_re: out std_ulogic; -- Write and read enable for I/O
		pause:         in std_ulogic; -- pause the CPU in the `S_FETCH` state
		blocked:      out std_ulogic; -- is the CPU paused, or blocking on I/O?
		halted:       out std_ulogic); -- Is the system halted?
end;

architecture rtl of lfsr is
	type state_t is (
		S_FETCH,    -- Load instruction
		S_INDIRECT, -- Indirect through operand
		S_STORE,    -- Store instruction
		S_LOAD,     -- Load instruction
		S_NEXT,     -- No Jump, load next PC
		S_IN,       -- Wait for input
		S_OUT       -- Output byte when ready
	);

	type alu_t is (
		A_XOR,   -- XOR accumulator with operand/loaded value
		A_AND,   -- AND accumulator with operand/loaded value
		A_LSL1,  -- Shift accumulator left by 1
		A_LSR1,  -- Shift accumulator right by 1
		A_LOAD,  -- Load through operand or already loaded value to accumulator 
		A_STORE, -- Store accumulator to operand or loaded value
		A_JMP,   -- Unconditional Jump
		A_JMPZ   -- Conditional Jump
	);

	type registers_t is record
		acc:   std_ulogic_vector(N - 1 downto 0); -- Multi purpose register
		val:   std_ulogic_vector(N - 1 downto 0); -- Value loaded or just the operand
		pc:    std_ulogic_vector(pc_length - 1 downto 0); -- Program Counter
		alu:   alu_t;   -- Used to store instruction
		state: state_t; -- CPU State Register
	end record;

	constant registers_default: registers_t := (
		acc   => (others => '0'),
		val   => (others => '0'),
		pc    => (others => '0'),
		alu   => A_XOR,
		state => S_FETCH);

	signal c, f: registers_t := registers_default; -- All state is captured in here
	signal jump, zero, dop: std_ulogic := '0'; -- Transient CPU Flags
	signal npc, opc: std_ulogic_vector(pc_length - 1 downto 0) := (others => '0'); -- Potential next PC value
	signal ra, rb, rout, raddr: std_ulogic_vector(N - 1 downto 0) := (others => '0');
	signal state, rstate: state_t := S_FETCH;
	signal alu: alu_t := A_XOR;

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0'); -- All Zeros

	-- These constants are used to index into the jump specification, this allows
	-- us to make alternative OISC machines by specifying a generic instead of making
	-- an entirely new machine.
	constant JS_C:   integer := 0; -- Jump on all condition or'd = '1' or '0'
	constant JS_ZEN: integer := 1; -- Enable Jumping on zero comparison 
	constant JS_ZC:  integer := 2; -- '1' = Jump on Zero, '0' = Jump on Non-Zero if enabled
	constant JS_NEN: integer := 3; -- Enable Jumping on negative (high bit set)
	constant JS_NC:  integer := 4; -- '1' = Jump on Negative, '0' = Jump on 

	-- Obviously this does not synthesize, which is why synthesis is turned
	-- off for the body of this procedure, it does make debugging much easier
	-- when running a test-bench as we will be able to see which instructions are 
	-- executed and do so by name.
	procedure print_debug_info is
		variable oline: line;
		function int(slv: in std_ulogic_vector) return string is
		begin
			return integer'image(to_integer(signed(slv)));
		end function;
		function uint(slv: in std_ulogic_vector) return string is
		begin
			return integer'image(to_integer(unsigned(slv)));
		end function;
	begin
		-- synthesis translate_off
		-- When `debug = 2` we can produce output that should be the same as our
		-- C simulator when it has debugging turned on (modulo some extra messages
		-- the VHDL test bench produces which should be obvious in a diff).
		if debug = 2 then
--			if c.state = S_ALU then
--				write(oline, uint(c.pc) & ": ");
--				write(oline, alu_t'image(c.alu) & " ");
--				write(oline, uint(c.acc));
--				writeline(OUTPUT, oline);
--			end if;
		end if;
		-- This debug mode shows the registers and their intermediate values when
		-- different states are entered, which is not possible (or needed) for the C 
		-- simulator. State transitions can also be shown explicitly when they occur.
		if debug >= 3 then
			write(oline, uint(c.pc)  & ": ");
			write(oline, state_t'image(c.state) & HT);
			write(oline, int(c.acc)   & " ");
			write(oline, alu_t'image(c.alu)   & " ");
			if debug >= 4 and c.state /= f.state then
				write(oline, state_t'image(c.state) & " => ");
				write(oline, state_t'image(f.state));
			end if;
			writeline(OUTPUT, oline);
		end if;
		-- synthesis translate_on
	end procedure;

begin
	-- The following asserts could be placed in this module if what
	-- they were asserting was "buffered". As they are not, they go
	-- in the next module up.
	--
	--   assert not (re = '1' and we = '1') severity warning;
	--   assert not (io_re = '1' and io_we = '1') severity warning;

	assert N >= 8 report "LFSR machine width too small, must be greater or equal to 8 bits" severity failure;

	pc_lfsr: if pc_is_lfsr generate -- Super RAD Mode
		gloop: for g in pc_length - 1 downto 0 generate
			ghi: if g = pc_length - 1 generate npc(g) <= c.pc(0) after delay; end generate;
			gnormal: if g < (pc_length - 1) generate
				gshift: if polynomial(g) = '0' generate npc(g) <= c.pc(g + 1) after delay; end generate;
				gxor: if polynomial(g) = '1' generate npc(g) <= c.pc(g + 1) xor c.pc(0) after delay; end generate;
			end generate;
		end generate;
	end generate;

	pc_counter: if not pc_is_lfsr generate -- Boring mode
		npc <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;
	end generate;

	zero  <= '1' when jspec(JS_ZEN) = '1' and c.acc = AZ else '0' after delay;
	jump  <= '1' when (jspec(JS_NEN) = '1' and c.acc(c.acc'high) = jspec(JS_NC)) or zero = jspec(JS_ZC) else '0' after delay;
	o     <= c.acc after delay;
	obyte <= c.acc(obyte'range) after delay;
	re    <= not dop after delay;
	we    <= dop after delay;

	process (clk, rst) 
	begin
		-- This used to just set `c.state` into a reset state, which no longer
		-- exists, instead of setting all registers to their default values. 
		-- This was removed to make the system as small as possible. 
		if rst = '1' and asynchronous_reset then
			c <= registers_default after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c <= registers_default after delay;
			else
				print_debug_info;
--				if c.state = S_FETCH then 
--					assert (f.state = S_FETCH and pause = '1') or f.state = S_INDIRECT or f.state = S_ALU; 
--				end if;
--				if c.state = S_INDIRECT then assert f.state = S_ALU; end if;
--				if c.state = S_ALU then assert f.state /= S_INDIRECT and f.state /= S_NEXT; end if;
--				if c.state = S_LOAD then assert f.state = S_NEXT; end if;
--				if c.state = S_STORE then assert f.state = S_NEXT; end if;
--				if c.state = S_IN then assert f.state = S_IN or f.state = S_NEXT; end if;
--				if c.state = S_OUT then assert f.state = S_OUT or f.state = S_NEXT; end if;
			end if;
		end if;
	end process;

	process (jump, npc, ra, rb, alu)
	begin
		rout <= ra after delay;
		raddr <= (others => '0') after delay;
		raddr(npc'range) <= npc after delay;
		opc <= npc after delay;
		rstate <= S_FETCH after delay;
		case alu is
		when A_XOR => rout <= ra xor rb after delay;
		when A_AND => rout <= ra and rb after delay;
		when A_LSL1 => 
			if replace_lsl1 then rout <= std_ulogic_vector(unsigned(ra) + unsigned(rb)) after delay;
			else rout <= ra(ra'high - 1 downto 0) & "0" after delay; end if;
		when A_LSR1 => rout <= "0" & ra(ra'high downto 1) after delay;
		when A_LOAD => raddr <= rb after delay; rstate <= S_LOAD after delay; if rb(rb'high) = '1' then rstate <= S_IN after delay; end if;
		when A_STORE => raddr <= rb after delay; rstate <= S_STORE after delay; if rb(rb'high) = '1' then rstate <= S_OUT after delay; end if;
		when A_JMP => raddr <= rb after delay; opc <= rb(opc'range) after delay; rstate <= S_FETCH after delay; 
			--if halt_enable and rb(c.pc'range) = c.pc then halted <= '1' after delay; end if;
		when A_JMPZ => if jump = jspec(JS_C) then raddr <= rb after delay; opc <= rb(opc'range) after delay; rstate <= S_FETCH after delay; end if;
		end case;
	end process;

	rb <= i after delay;
	ra <= c.acc after delay;

	process (c, i, ibyte, obsy, ihav, pause, rout, raddr, rstate, opc) 
		alias indirect is i(i'high);
		alias alubits is i(i'high - 1 downto i'high - 3);
		alias operand is i(i'high - 4 downto 0);
	begin
		f      <= c after delay;
		halted <= '0' after delay;
		io_we  <= '0' after delay;
		io_re  <= '0' after delay;
		dop    <= '0' after delay; -- read enabled when `dop='0'`, write otherwise
		a      <= (others => '0') after delay;
		a(c.pc'range) <= c.pc after delay;
		blocked <= '0' after delay;
		alu <= alu_t'val(to_integer(unsigned(alubits))) after delay;

		case c.state is
		when S_FETCH =>
			f.alu <= alu_t'val(to_integer(unsigned(alubits))) after delay;
			f.val <= (others => '0') after delay;
			f.val(operand'range) <= operand after delay;
			if pause = '1' then
				f.state <= S_FETCH after delay;
			elsif indirect = '1' then
				a <= (others => '0');
				a(operand'range) <= operand after delay;
				f.state <= S_INDIRECT after delay;
			else
				a <= raddr after delay;
				f.acc <= rout after delay;
				f.state <= rstate after delay;
				f.pc <= opc after delay;
			end if;
		when S_INDIRECT =>
			alu <= c.alu after delay;
			a <= raddr after delay;
			f.val <= i after delay;
			f.acc <= rout after delay;
			f.pc <= opc after delay;
			f.state <= rstate after delay;
		when S_STORE =>
			a <= c.val after delay;
			dop <= '1' after delay;
			f.state <= S_NEXT after delay;
		when S_LOAD =>
			a <= c.val after delay;
			f.acc <= i after delay;
			f.state <= S_NEXT after delay;
		when S_NEXT =>
			f.state <= S_FETCH after delay;
			a(c.pc'range) <= c.pc after delay;
		-- The I/O could be reworked, it does not need to be part of the
		-- the CPU, it just makes implemented a UART driven eForth interface
		-- easier as it behaves much like the C VM. The rework would entail
		-- is removing the `S_IN` and `S_OUT` states along with associated
		-- signals and handling I/O with proper memory mapping with `S_LOAD`
		-- and `S_STORE`. This would require software changes as well.
		when S_IN => 
			if multiple_io then
				a <= c.val after delay; -- Used so an external I/O system can determine what we are reading from (if needed)
			end if;
			f.acc <= (others => '0') after delay;
			f.acc(ibyte'range) <= ibyte after delay;
			blocked <= '1' after delay;
			if ihav = '1' then
				f.state <= S_NEXT after delay;
				io_re   <= '1' after delay;
				blocked <= '0' after delay;
			elsif non_blocking_input then
				f.state <= S_NEXT after delay;
				f.acc   <= (others => '1') after delay;
				blocked <= '0' after delay;
			end if;
		when S_OUT =>
			if multiple_io then
				a <= c.val after delay; -- Used so an external I/O system can determine what we are writing to (if needed)
			end if;
			blocked <= '1' after delay;
			if obsy = '0' then
				f.state <= S_NEXT after delay;
				io_we   <= '1' after delay;
				blocked <= '0' after delay;
			end if;
		end case;
	end process;
end architecture;

