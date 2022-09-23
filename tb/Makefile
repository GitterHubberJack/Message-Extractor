VSIM_CMDS?="run 20 us; quit"
VSIM_OPTS?=
ELAB_OPTS?=
TOP?= top

all: clean compile optimize elaborate simulate 

compile:
	vlog -64 -sv -f files.vc  | tee vlog.log
optimize:
	vopt -64 +acc $(TOP) -designfile $(TOP).bin -o $(TOP)_vopt | tee vopt.log 

elaborate:
	vsim -64 -elab $(TOP).elab -compress_elab $(TOP)_vopt $(ELAB_OPTS)  | tee elab.log

simulate:
	vsim -64 -c -load_elab $(TOP).elab $(VSIM_OPTS) +notimingchecks -qwavedb=memory+signal+wavefile=$(TOP).db -do $(VSIM_CMDS) | tee vsim.log

view:
	visualizer -designfile $(TOP).bin -wavefile $(TOP).db -do Wave0.do

view_vcd:
	vcd2wlf wave.vcd wave.wlf
	vsim wave.wlf

clean:
	rm -rf work
	rm -f *.log
	rm -f *.jou
	rm -f *.elab
	rm -f *_vopt
	rm -f *.bin
	rm -f *.db
	rm -f *.so
	rm -f *.vstf
	rm -f *.vcd
	rm -f *.wlf
	rm -f modelsim.in
	rm -f transcript
