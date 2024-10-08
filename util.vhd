-- File:        util.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/lfsr-vhdl
-- Email:       howe.r.j.89@gmail.com
-- License:     0BSD / Public Domain
--
-- Description: Utility module, mostly taken from another project
-- of mine, <https://github.com/howerj/forth-cpu>.
--

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package util is
	-- Not all modules will need every generic specified here, even so it
	-- is easier to group the common generics in one structure.
	type common_generics is record
		clock_frequency:    positive; -- clock frequency of module clock
		delay:              time;     -- gate delay for simulation purposes
		asynchronous_reset: boolean;  -- use asynchronous reset if true
	end record;

	constant default_settings: common_generics := (
		clock_frequency    => 100_000_000,
		delay              => 0 ns,
		asynchronous_reset => true
	);

	type file_format is (FILE_HEX, FILE_BINARY, FILE_DECIMAL, FILE_NONE);

	component single_port_block_ram is
	generic (g: common_generics;
		addr_length: positive    := 12;
		data_length: positive    := 16;
		file_name:   string      := "memory.bin";
		file_type:   file_format := FILE_BINARY);
	port (
		clk:  in  std_ulogic;
		dwe:  in  std_ulogic;
		dre:  in  std_ulogic;
		addr: in  std_ulogic_vector(addr_length - 1 downto 0);
		din:  in  std_ulogic_vector(data_length - 1 downto 0);
		dout: out std_ulogic_vector(data_length - 1 downto 0) := (others => '0'));
	end component;

	function hex_char_to_std_ulogic_vector_tb(hc: character) return std_ulogic_vector;


	-- synthesis translate_off
	subtype configuration_name is string(1 to 8);

	type configuration_item is record
		name:  configuration_name;
		value: integer;
	end record;

	type configuration_items is array(integer range <>) of configuration_item;

	function search_configuration_tb(find_me: configuration_name; ci: configuration_items) return integer;
	procedure read_configuration_tb(file_name:  string; ci: inout configuration_items);
	procedure write_configuration_tb(file_name: string; ci: configuration_items);
	-- synthesis translate_on
end;

package body util is
	function hex_char_to_std_ulogic_vector_tb(hc: character) return std_ulogic_vector is
		variable slv: std_ulogic_vector(3 downto 0);
	begin
		case hc is
		when '0' => slv := "0000";
		when '1' => slv := "0001";
		when '2' => slv := "0010";
		when '3' => slv := "0011";
		when '4' => slv := "0100";
		when '5' => slv := "0101";
		when '6' => slv := "0110";
		when '7' => slv := "0111";
		when '8' => slv := "1000";
		when '9' => slv := "1001";
		when 'A' => slv := "1010";
		when 'a' => slv := "1010";
		when 'B' => slv := "1011";
		when 'b' => slv := "1011";
		when 'C' => slv := "1100";
		when 'c' => slv := "1100";
		when 'D' => slv := "1101";
		when 'd' => slv := "1101";
		when 'E' => slv := "1110";
		when 'e' => slv := "1110";
		when 'F' => slv := "1111";
		when 'f' => slv := "1111";
		when others => slv := "XXXX";
		end case;
		assert (slv /= "XXXX") report " not a valid hex character: " & hc  severity failure;
		return slv;
	end;

	-- synthesis translate_off

	-- Find a string in a configuration items array, or returns -1 on
	-- failure to find the string.
	function search_configuration_tb(find_me: configuration_name; ci: configuration_items) return integer is
	begin
		for i in ci'range loop
			if ci(i).name = find_me then
				return i;
			end if;
		end loop;
		return -1;
	end;

	-- VHDL provides quite a limited set of options for dealing with
	-- operations that are not synthesizeable but would be useful for
	-- use in test benches. This method provides a crude way of reading
	-- in configurable options. It has a very strict format.
	--
	-- The format is line oriented, it expects a string on a line
	-- with a length equal to the "configuration_name" type, which
	-- is a subtype of "string". It finds the corresponding record
	-- in configuration_items if it exists. It then reads in an
	-- integer from the next line and sets the record for it.
	--
	-- Any deviation from this format causes an error and the simulation
	-- to halt, whilst not a good practice to do error checking with asserts
	-- there is no better way in VHDL in this case. The only sensible
	-- action on an error would for the configuration file to be fixed
	-- anyway.
	--
	-- Comment lines and variable length strings would be nice, but
	-- are too much of a hassle.
	--
	-- The configuration function only deal with part of the configuration
	-- process, it does not deal with deserialization into structures
	-- more useful to the user - that is into individual signals.
	--
	procedure read_configuration_tb(file_name: string; ci: inout configuration_items) is
		file     in_file: text is in file_name;
		variable in_line: line;
		variable d:       integer;
		variable s:       configuration_name;
		variable index:   integer;
	begin
		while not endfile(in_file) loop

			readline(in_file, in_line);
			read(in_line, s);
			index := search_configuration_tb(s, ci);

			assert index >= 0 report "Unknown configuration item: " & s severity failure;

			readline(in_file, in_line);
			read(in_line, d);

			ci(index).value := d;

			report "Config Item: '" & ci(index).name & "' = " & integer'image(ci(index).value);
		end loop;
		file_close(in_file);
	end procedure;

	procedure write_configuration_tb(file_name: string; ci: configuration_items) is
		file     out_file: text is out file_name;
		variable out_line: line;
	begin
		for i in ci'range loop
			write(out_line, ci(i).name);
			writeline(out_file, out_line);
			write(out_line, ci(i).value);
			writeline(out_file, out_line);
		end loop;
	end procedure;

	-- synthesis translate_on

end;

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.util.all;

entity single_port_block_ram is
	generic (g: common_generics;
		addr_length: positive    := 12;
		data_length: positive    := 16;
		file_name:   string      := "memory.bin";
		file_type:   file_format := FILE_BINARY);
	port (
		clk:  in  std_ulogic;
		dwe:  in  std_ulogic;
		dre:  in  std_ulogic;
		addr: in  std_ulogic_vector(addr_length - 1 downto 0);
		din:  in  std_ulogic_vector(data_length - 1 downto 0);
		dout: out std_ulogic_vector(data_length - 1 downto 0) := (others => '0'));
end entity;

-- The function `initialize_ram` does what it says, it initializes a Block RAM from a file, which
-- is read off of disk. Unfortunately this version does not synthesize in Xilinx ISE 14.7 (and likely
-- never will) because of an indefinite loop, failing with the error "Non-static loop limit exceeded".
--
-- This is a shame as this version is more flexible in what it can handle.
--
-- The function allows multiple file types to be used to initialize the RAM:
--
-- * FILE_HEX; A file containing hexadecimal values, one per line.
-- * FILE_BINARY; A file containing binary values, one per line.
-- * FILE_DECIMAL; A file consisting of signed decimal values, one per line.
-- * FILE_NONE; No file, all RAM contents will be initialized to 0.
--
-- ----------------------------------------------------------------------------------------------------------
--
-- impure function initialize_ram(the_file_name: in string; the_file_type: in file_format) return ram_type is
-- 	variable ram_data:   ram_type;
-- 	file     in_file:    text is in the_file_name;
-- 	variable input_line: line;
-- 	variable tmp:        bit_vector(data_length - 1 downto 0);
-- 	variable int:        integer;
-- 	variable i:          integer;
-- 	variable good:       boolean;
-- 	variable c:          character;
-- 	variable slv:        std_ulogic_vector(data_length - 1 downto 0);
-- begin
-- 	i := 0;
-- 	while i < ram_size loop
-- 		if the_file_type = FILE_NONE then
-- 			ram_data(i) := (others => '0');
-- 			i := i + 1;
-- 		elsif not endfile(in_file) then
-- 			readline(in_file,input_line);
-- 			if the_file_type = FILE_BINARY then
-- 				read(input_line, tmp);
-- 				ram_data(i) := std_ulogic_vector(to_stdlogicvector(tmp));
-- 				i := i + 1;
-- 			elsif the_file_type = FILE_DECIMAL then
-- 				good := true;
-- 				while good and i < ram_size loop
-- 					read(input_line, int, good);
-- 					if good then
-- 						if int < 0 then
-- 							int := (2**data_length) + int;
-- 						end if;
-- 						assert int < (2**data_length) and int >= 0 severity failure;
-- 						ram_data(i) := std_ulogic_vector(to_unsigned(int, tmp'length));
-- 						i := i + 1;
-- 					end if;
-- 				end loop;
-- 			elsif the_file_type = FILE_HEX then -- hexadecimal
-- 				assert (data_length mod 4) = 0 report "(data_length%4)!=0" severity failure;
-- 				for j in 1 to (data_length/4) loop
-- 					c:= input_line((data_length/4) - j + 1);
-- 					slv((j*4)-1 downto (j*4)-4) := hex_char_to_std_ulogic_vector_tb(c);
-- 				end loop;
-- 				ram_data(i) := slv;
-- 				i := i + 1;
-- 			else
-- 				report "Incorrect file type given: " & file_format'image(the_file_type) severity failure;
-- 			end if;
-- 		else
-- 			ram_data(i) := (others => '0');
-- 			i := i + 1;
-- 		end if;
-- 	end loop;
-- 	file_close(in_file);
-- 	return ram_data;
-- end function;
--
-- ----------------------------------------------------------------------------------------------------------

architecture behav of single_port_block_ram is
	constant ram_size: positive := 2 ** addr_length;

	type ram_type is array ((ram_size - 1) downto 0) of std_ulogic_vector(data_length - 1 downto 0);

	impure function initialize_ram(the_file_name: in string; the_file_type: in file_format) return ram_type is
		variable ram_data:   ram_type;
		file     in_file:    text is in the_file_name;
		variable input_line: line;
		variable tmp:        bit_vector(data_length - 1 downto 0);
		variable int:        integer;
		variable c:          character;
		variable slv:        std_ulogic_vector(data_length - 1 downto 0);
	begin
		for i in 0 to ram_size - 1 loop
			if the_file_type = FILE_NONE then
				ram_data(i) := (others => '0');
			elsif not endfile(in_file) then
				readline(in_file,input_line);
				if the_file_type = FILE_BINARY then
					read(input_line, tmp);
					ram_data(i) := std_ulogic_vector(to_stdlogicvector(tmp));
				elsif the_file_type = FILE_DECIMAL then
					read(input_line, int);
					if int < 0 then
						int := (2 ** data_length) + int;
					end if;
					assert int < (2 ** data_length) and int >= 0 severity failure;
					ram_data(i) := std_ulogic_vector(to_unsigned(int, tmp'length));
				elsif the_file_type = FILE_HEX then -- hexadecimal
					assert (data_length mod 4) = 0 report "(data_length % 4) != 0" severity failure;
					for j in 1 to (data_length / 4) loop
						c:= input_line((data_length / 4) - j + 1);
						slv((j * 4) - 1 downto (j * 4) - 4) := hex_char_to_std_ulogic_vector_tb(c);
					end loop;
					ram_data(i) := slv;
				else
					report "Incorrect file type given: " & file_format'image(the_file_type) severity failure;
				end if;
			else
				ram_data(i) := (others => '0');
			end if;
		end loop;
		file_close(in_file);
		return ram_data;
	end function;

	shared variable ram: ram_type := initialize_ram(file_name, file_type);
begin
	block_ram: process(clk)
	begin
		if rising_edge(clk) then
			if dwe = '1' then
				ram(to_integer(unsigned(addr))) := din;
			end if;

			if dre = '1' then
				dout <= ram(to_integer(unsigned(addr))) after g.delay;
			else
				dout <= (others => '0') after g.delay;
			end if;
		end if;
	end process;
end architecture;
