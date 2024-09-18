-- File:        lfsr.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/lfsr-vhdl
-- License:     MIT / Public Domain
-- Description: CPU with LFSR as PC

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- Used for debug only (turned off for synthesis)

entity lfsr is
	generic (
		asynchronous_reset: boolean    := true;   -- use asynchronous reset if true, synchronous if false
		delay:              time       := 0 ns;   -- simulation only, gate delay
		N:                  positive   := 16;     -- size the CPU
		lfsr_length:        positive   := 8;      -- size of the LFSR polynomial
		jspec:              std_ulogic_vector(4 downto 0) := "11100"; -- Jump specification
		polynomial:         std_ulogic_vector(7 downto 0) := x"B8";
		non_blocking_input: boolean    := false;  -- if true, input will be -1 if there is no input
		strict_io:          boolean    := true;   -- if true, I/O happens when `a` or `b` are -1, else when high bit set
		pc_is_lfsr:         boolean    := true;   -- switch between using a counter and using a LFSR
		debug:              natural    := 0);     -- debug level, 0 = off
	port (
		clk:           in std_ulogic; -- Guess what this is?
		rst:           in std_ulogic; -- Can be sync or async
		o:            out std_ulogic_vector(N - 1 downto 0); -- Memory access; Output
		i:             in std_ulogic_vector(N - 1 downto 0); -- Memory access; Input
		a:            out std_ulogic_vector(N - 1 downto 0); -- Memory access; Address
		we, re:       out std_ulogic; -- Write and read enable for memory only
		obyte:        out std_ulogic_vector(7 downto 0); -- UART output byte
		ibyte:         in std_ulogic_vector(7 downto 0); -- UART input byte
		obsy, ihav:    in std_ulogic; -- Output busy / Have input
		io_we, io_re: out std_ulogic; -- Write and read enable for I/O (UART)
		pause:         in std_ulogic; -- pause the CPU in the `S_FETCH` state
		blocked:      out std_ulogic; -- is the CPU paused, or blocking on I/O?
		halted:       out std_ulogic); -- Is the system halted?
end;

architecture rtl of lfsr is
	type state_t is (
		S_RESET,  -- Starting State
		S_FETCH, -- Load instruction
		S_INDIRECT, -- Indirect through operand
		S_ALU,    -- ALU instruction
		S_STORE,  -- Store instruction
		S_LOAD,   -- Load instruction
		S_NEXT,   -- No Jump
		S_IN,     -- Wait for input
		S_OUT,    -- Output byte when ready
		S_HALT);  -- Stop for it is the time of hammers

	-- TODO: Customizable Program Counter, LFSR N-Bit vs Program Counter N-Bit
	type registers_t is record
		acc:    std_ulogic_vector(N - 1 downto 0); -- Multi purpose register
		val:    std_ulogic_vector(N - 1 downto 0);
		pc:     std_ulogic_vector(lfsr_length - 1 downto 0); -- Program Counter
		alu:    std_ulogic_vector(2 downto 0);
		state:  state_t;    -- CPU State Register
		stop:   std_ulogic; -- CPU Halt Flag
		indirect: std_ulogic; 
	end record;

	constant registers_default: registers_t := (
		acc    => (others => '0'),
		val    => (others => '0'),
		pc     => (others => '0'),
		alu    => (others => '0'),
		state  => S_RESET,
		stop   => '0',
		indirect => '0');

	signal c, f: registers_t := registers_default; -- All state is captured in here
	signal jump, zero, dop, feedback: std_ulogic := '0'; -- Transient CPU Flags
	signal npc: std_ulogic_vector(7 downto 0) := (others => '0');

	constant AZ: std_ulogic_vector(N - 1 downto 0) := (others => '0'); -- All Zeros
	constant AO: std_ulogic_vector(N - 1 downto 0) := (others => '1'); -- All Ones

	-- These constants are used to index into the jump specification, this allows
	-- us to make alternative OISC machines by specifying a generic instead of making
	-- an entirely new machine.
	constant JS_C:   integer := 0; -- Jump on all condition or'd = '1' or '0'
	constant JS_ZEN: integer := 1; -- Enable Jumping on zero comparison 
	constant JS_ZC:  integer := 2; -- '1' = Jump on Zero, '0' = Jump on Non-Zero if enabled
	constant JS_NEN: integer := 3; -- Enable Jumping on negative (high bit set)
	constant JS_NC:  integer := 4; -- '1' = Jump on Negative, '0' = Jump on 

	-- Obviously this does not synthesize, which is why synthesis is turned
	-- off for the body of this function, it does make debugging much easier
	-- though, we will be able to see which instructions are executed and do so
	-- by name.
	--
	-- TODO: Print out the same debug information as `lfsr.c` so they can be
	-- compared directly
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
		if debug >= 2 then
			write(oline, uint(c.pc)  & ": ");
			write(oline, state_t'image(c.state) & HT);
			write(oline, int(c.acc)   & " ");
			write(oline, uint(c.alu)   & " "); -- TODO: Print out ALU instruction name
			--write(oline, c.indirect'image   & " ");
			if debug >= 3 and c.state /= f.state then
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

	assert lfsr_length = polynomial'length severity failure;
	assert N >= 8 report "LFSR machine width too small, must be greater or equal to 8 bits" severity failure;

	-- TODO: Optional counter / LFSR next state
	pc_lfsr: if pc_is_lfsr generate
		-- TODO: Generate from polynomial string / different LFSR types
		--feedback <= c.pc(7) xor c.pc(5) xor c.pc(4) xor c.pc(3) after delay;
		--npc <= feedback & c.pc(c.pc'high downto 1) after delay;
		npc <= "0" & c.pc(c.pc'high downto 1) when c.pc(0) = '0' else (polynomial xor ("0" & c.pc(c.pc'high downto 1))) after delay;
--		npc(7) <= c.pc(0) after delay;
--		npc(6) <= c.pc(7) after delay;
--		npc(5) <= c.pc(6) after delay;
--		npc(4) <= c.pc(5) after delay;
--		npc(3) <= c.pc(4) after delay;
--		npc(2) <= c.pc(3) after delay;
--		npc(1) <= c.pc(2) after delay;
--		npc(0) <= c.pc(1) after delay;
	end generate;

	pc_counter: if not pc_is_lfsr generate
		npc  <= std_ulogic_vector(unsigned(c.pc) + 1) after delay;
	end generate;

	--zero  <= '1' when jspec(JS_ZEN) = '1' and c.acc = AZ else '0' after delay;
	--jump  <= '1' when (jspec(JS_NEN) = '1' and c.acc(c.acc'high) = jspec(JS_NC)) or zero = jspec(JS_ZC) else '0' after delay;
	zero  <= '1' when c.acc = AZ else '0' after delay;
	jump  <= zero after delay;
	o     <= c.acc after delay;
	obyte <= c.acc(obyte'range) after delay;
	re    <= not dop after delay;
	we    <= dop after delay;

	process (clk, rst) begin
		if rst = '1' and asynchronous_reset then
			c.state <= S_RESET after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not asynchronous_reset then
				c.state <= S_RESET after delay;
			else
				print_debug_info; -- TODO: Assert next state
			end if;
		end if;
	end process;

	process (c, i, npc, jump, ibyte, obsy, ihav, pause) begin
		f <= c after delay;
		halted <= '0' after delay;
		io_we <= '0' after delay;
		io_re <= '0' after delay;
		dop <= '0' after delay; -- read enabled when `dop='0'`, write otherwise
		a <= (others => '0') after delay;
		a(c.pc'range) <= c.pc after delay;
		blocked <= '0' after delay;
		--if c.pc(c.pc'high) = '1' then f.stop <= '1' after delay; end if;

		case c.state is
		when S_RESET => 
			f <= registers_default after delay;
			f.state <= S_FETCH after delay;
			a <= (others => '0') after delay;
		when S_FETCH =>
			f.state <= S_ALU after delay;
			f.alu <= i(i'high - 1 downto i'high - 3) after delay;
			f.indirect <= i(i'high) after delay;
			f.val <= (others => '0') after delay;
			f.val(i'high - 4 downto 0) <= i(i'high - 4 downto 0) after delay;
			if pause = '1' then
				f.state <= S_FETCH after delay;
			elsif i(i'high) = '1' then
				--a <= f.val after delay;
				a <= (others => '0');
				a(i'high - 4 downto 0) <= i(i'high - 4 downto 0) after delay;
				f.state <= S_INDIRECT after delay;
			end if;
		when S_INDIRECT =>
			a <= c.val after delay;
			f.val <= i after delay;
			f.state <= S_ALU after delay;
		when S_ALU => -- TODO: Is this state needed? Optimize states
			f.state <= S_NEXT after delay;
			a(npc'range) <= npc after delay;
			case c.alu is
			when "000" => f.acc <= c.acc and c.val after delay;
			when "001" => f.acc <= c.acc xor c.val after delay;
			when "010" => f.acc <= c.acc(c.acc'high - 1 downto 0) & "0" after delay;
			when "011" => f.acc <= "0" & c.acc(c.acc'high downto 1) after delay;
			when "100" => a <= c.val after delay; f.state <= S_LOAD after delay; if c.val(f.val'high) = '1' then f.state <= S_IN after delay; end if;
			when "101" => a <= c.val after delay; f.state <= S_STORE after delay; if c.val(f.val'high) = '1' then f.state <= S_OUT after delay; end if;
			when "110" => a <= c.val after delay; f.pc <= c.val(f.pc'range) after delay; f.state <= S_FETCH after delay; -- TODO: Halt condition
			when "111" => if jump = '1' then a <= c.val after delay; f.pc <= c.val(f.pc'range) after delay; f.state <= S_FETCH after delay; end if;
			when others =>
			end case;
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
			a(npc'range) <= npc after delay;
			f.pc <= npc after delay;
		when S_IN => -- TODO: Rework I/O to be memory mapped properly?
			f.acc <= (others => '0') after delay;
			f.acc (ibyte'range) <= ibyte after delay;
			blocked <= '1' after delay;
			if ihav = '1' then
				f.state <= S_NEXT after delay;
				io_re <= '1' after delay;
				blocked <= '0' after delay;
			elsif non_blocking_input then
				f.state <= S_NEXT after delay;
				f.acc <= (others => '1') after delay;
				blocked <= '0' after delay;
			end if;
		when S_OUT =>
			blocked <= '1' after delay;
			if obsy = '0' then
				f.state <= S_NEXT after delay;
				io_we <= '1' after delay;
				blocked <= '0' after delay;
			end if;
		when S_HALT =>
			halted <= '1' after delay;
		end case;
	end process;
end architecture;

