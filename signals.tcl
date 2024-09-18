# Richard James Howe
# TCL Script for GTKWave on tb.ghw
#

gtkwave::/Edit/Set_Trace_Max_Hier 0
gtkwave::/Time/Zoom/Zoom_Amount -27.0
gtkwave::/View/Show_Filled_High_Values 1
#gtkwave::setFromEntry 170ns

set names {
	top.tb.rst
	top.tb.clk
	top.tb.gn.uut.system.cpu.a[15:0]
	top.tb.gn.uut.system.cpu.o[15:0]
	top.tb.gn.uut.system.cpu.i[15:0]
	top.tb.gn.uut.system.cpu.c.state
	top.tb.gn.uut.system.cpu.c.pc[7:0]
	top.tb.gn.uut.system.cpu.c.acc[15:0]
	top.tb.gn.uut.system.cpu.c.arg[15:0]
	top.tb.gn.uut.system.cpu.c.alu[2:0]
	top.tb.gn.uut.system.cpu.c.indirect
	top.tb.gn.uut.system.cpu.c.stop
	top.tb.gn.uut.system.cpu.npc[7:0]
	top.tb.gn.uut.system.cpu.re
	top.tb.gn.uut.system.cpu.we
	top.tb.gn.uut.system.cpu.io_re
	top.tb.gn.uut.system.cpu.io_we
	top.tb.gn.uut.system.cpu.halted
	top.tb.gn.uut.system.cpu.blocked
	top.tb.gn.uut.obyte[7:0]
	top.tb.gn.uut.ibyte[7:0]
	top.tb.gt.uut.system.cpu.a[15:0]
	top.tb.gt.uut.system.cpu.o[15:0]
	top.tb.gt.uut.system.cpu.i[15:0]
	top.tb.gt.uut.system.cpu.c.state
	top.tb.gt.uut.system.cpu.c.pc[7:0]
	top.tb.gt.uut.system.cpu.c.acc[15:0]
	top.tb.gt.uut.system.cpu.c.val[15:0]
	top.tb.gt.uut.system.cpu.c.alu[2:0]
	top.tb.gt.uut.system.cpu.c.indirect
	top.tb.gt.uut.system.cpu.c.stop
	top.tb.gt.uut.system.cpu.npc[7:0]
	top.tb.gt.uut.system.cpu.re
	top.tb.gt.uut.system.cpu.we
	top.tb.gt.uut.system.cpu.io_re
	top.tb.gt.uut.system.cpu.io_we
	top.tb.gt.uut.system.cpu.halted
	top.tb.gt.uut.system.cpu.blocked
	top.tb.gt.uut.obyte[7:0]
	top.tb.gt.uut.ibyte[7:0]
	top.tb.tx
	top.tb.rx
}

gtkwave::addSignalsFromList $names

foreach v $names {
	set a [split $v .]
	set a [lindex $a end]
	gtkwave::highlightSignalsFromList $v
	gtkwave::/Edit/Alias_Highlighted_Trace $a
	gtkwave::/Edit/UnHighlight_All $a
}

