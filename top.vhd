-- File:        top.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/lfsr-vhdl
-- Email:       howe.r.j.89@gmail.com
-- License:     0BSD / Public Domain
-- Description: Top level entity; LFSR CPU
--
-- This module brings together the LFSR CPU/Memory subsystem with
-- the I/O, which is a UART.

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.all;
use work.uart_pkg.all;

entity top is
	generic (
		g:               common_generics := default_settings;
		file_name:       string          := "lfsr.hex";
		N:               positive        := 16;
		baud:            positive        := 115200;
		debug:           natural         := 0; -- will not synthesize if greater than zero (debug off = 0)
		halt_enable:     boolean         := false
	);
	port (
		clk:         in std_ulogic;
		-- synthesis translate_off
--		rst:         in std_ulogic;
		halted:     out std_ulogic;
		blocked:    out std_ulogic;
		-- synthesis translate_on
		tx:         out std_ulogic;
		rx:          in std_ulogic);
end entity;

architecture rtl of top is
	constant clks_per_bit: integer  := calc_clks_per_bit(g.clock_frequency, baud);
	constant delay:        time     := g.delay;

	signal rst: std_ulogic := '0';

	type registers_t is record
		hav: std_ulogic;
		ibyte: std_ulogic_vector(7 downto 0);
	end record;

	constant registers_default: registers_t := (
		hav => '0',
		ibyte => (others => '0')
	);

	signal c, f: registers_t := registers_default;

	signal bsy, hav, io_re, io_we: std_ulogic := 'U';
	signal obyte, ibyte: std_ulogic_vector(7 downto 0) := (others => 'U');
begin
	assert not (io_re = '1' and io_we = '1') severity warning;

	process (clk, rst) begin -- N.B. We could use register components for this
		if rst = '1' and g.asynchronous_reset then
			c <= registers_default after delay;
		elsif rising_edge(clk) then
			c <= f after delay;
			if rst = '1' and not g.asynchronous_reset then
				c <= registers_default after delay;
			end if;
		end if;
	end process;

	process (c, hav, ibyte, io_re) begin
		f <= c after delay;

		if hav = '1' then
			f.hav <= '1' after delay;
			f.ibyte <= ibyte after delay;
		end if;

		if io_re = '1' then
			f.hav <= '0' after delay;
		end if;
	end process;

	system: entity work.system
	generic map(
		g => g,
		file_name => file_name,
		N => N,
		debug => debug,
		halt_enable => halt_enable)
	port map (
		clk     => clk,
		rst     => rst,
		-- synthesis translate_off
		halted  => halted,
		blocked => blocked,
		-- synthesis translate_on
		obyte   => obyte,
		ibyte   => c.ibyte,
		obsy    => bsy,
		ihav    => c.hav,
		io_we   => io_we, 
		io_re   => io_re);

	uart_tx_0: entity work.uart_tx
		generic map(clks_per_bit => clks_per_bit, delay => delay)
		port map(
			clk => clk,
			tx_we => io_we,
			tx_byte => obyte,
			tx_active => bsy,
			tx_serial => tx,
			tx_done => open);

	uart_rx_0: entity work.uart_rx
		generic map(clks_per_bit => clks_per_bit, delay => delay)
		port map(
			clk => clk,
			rx_serial => rx,
			rx_have_data => hav,
			rx_byte => ibyte);

end architecture;


