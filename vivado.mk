.PHONY: frac synth vivado tmpclean clean distclean

.PRECIOUS: %.xpr %.bit %.bin %.mcs %.prm

FPGA_TOP ?= frac_top
PROJECT ?= $(FPGA_TOP)

RTL_FILES_REL = $(foreach p,$(RTL_FILES),$(if $(filter /% ./%,$p),$p,$p))
IP_TCL_FILES_REL = $(foreach p,$(IP_TCL_FILES),$(if $(filter /% ./%,$p),$p,$p))
XCI_FILES_REL = $(foreach p,$(XCI_FILES),$(if $(filter /% ./%,$p),$p,$p))

ifdef XDC_FILES
  XDC_FILES_REL = $(foreach p,$(XDC_FILES),$(if $(filter /% ./%,$p),$p,$p))
else
  XDC_FILES_REL = $(PROJECT).xdc
endif

# Targets

all: ip frac

frac: $(PROJECT).bit

vivado: $(PROJECT).xpr
	vivado $(PROJECT).xpr

synth: $(PROJECT).runs/synth_1/$(PROJECT).dcp

tmpclean::
	-rm -rf *.log *.jou *.cache *.gen *.hbs *.hw *.ip_user_files *.runs *.xpr *.html *.xml *.sim *.srcs *.str .Xil defines.v
	-rm -rf create_project.tcl update_config.tcl run_synth.tcl run_impl.tcl generate_bit.tcl create_*.tcl run_*.tcl route.tcl
	-rm -rf generate_*.tcl route_*.tcl *.ioplanning
clean:: tmpclean
	-rm -rf *.bit *.bin *.ltx *.xsa program.tcl generate_mcs.tcl *.mcs *.prm flash.tcl *.dcp hd_visual
	-rm -rf *_utilization.rpt *_utilization_hierarchical.rpt
	-rm -rf xdc/pr_fpga.xdc

distclean:: clean
	-rm -rf rev

cleanall:: distclean clean_ip

# Target Implementations
# Vivado project file
create_project.tcl: Makefile $(IP_TCL_FILES_REL)
	rm -rf defines.v
	touch defines.v
	for x in $(DEFS); do echo '`define' $$x >> defines.v; done
	echo "create_project -force -part $(FPGA_PART) $(PROJECT)" > $@
	echo "set_property ip_repo_paths \"[file normalize build/lib]\" [current_project]" >> $@
	echo "add_files -fileset sources_1 defines.v $(RTL_FILES_REL)" >> $@
	echo "set_property top $(FPGA_TOP) [current_fileset]" >> $@
	echo "add_files -fileset constrs_1 $(XDC_FILES_REL)" >> $@
	for x in $(XCI_FILES_REL); do echo "import_ip $$x" >> $@; done
	for x in $(IP_TCL_FILES_REL); do echo "source $$x" >> $@; done

$(PROJECT).xpr: create_project.tcl
	vivado -nojournal -nolog -mode batch $(foreach x,$?,-source $x)

# synthesis run
$(PROJECT).runs/synth_1/$(PROJECT).dcp: create_project.tcl $(RTL_FILES_REL) $(INC_FILES_REL) $(XDC_FILES_REL) | $(PROJECT).xpr
	echo "open_project $(PROJECT).xpr" > run_synth.tcl
	echo "reset_run synth_1" >> run_synth.tcl
	echo "catch {set_property STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_MODE off [get_runs synth_1]}" >> run_synth.tcl
	echo "catch {set_property STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_CHECKPOINT {} [get_runs synth_1]}" >> run_synth.tcl
	echo "catch {set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]}" >> run_synth.tcl
	echo "launch_runs -jobs 4 synth_1" >> run_synth.tcl
	echo "wait_on_run synth_1" >> run_synth.tcl
	vivado -nojournal -nolog -mode batch -source run_synth.tcl

# implementation run
$(PROJECT).runs/impl_1/$(PROJECT)_routed.dcp: $(PROJECT).runs/synth_1/$(PROJECT).dcp
	echo "open_project $(PROJECT).xpr" > run_impl.tcl
	echo "reset_run impl_1" >> run_impl.tcl
	echo "launch_runs -jobs 4 impl_1" >> run_impl.tcl
	echo "wait_on_run impl_1" >> run_impl.tcl
	echo "open_run impl_1" >> run_impl.tcl
	echo "report_utilization -file $(PROJECT)_utilization.rpt" >> run_impl.tcl
	echo "report_utilization -hierarchical -file $(PROJECT)_utilization_hierarchical.rpt" >> run_impl.tcl
	vivado -nojournal -nolog -mode batch -source run_impl.tcl

# bit file
$(PROJECT).bit $(PROJECT).bin $(PROJECT).ltx $(PROJECT).xsa: $(PROJECT).runs/impl_1/$(PROJECT)_routed.dcp
	echo "open_project $(PROJECT).xpr" > generate_bit.tcl
	echo "open_run impl_1" >> generate_bit.tcl
	echo "write_bitstream -force -bin_file $(PROJECT).runs/impl_1/$(PROJECT).bit" >> generate_bit.tcl
	echo "write_debug_probes -force $(PROJECT).runs/impl_1/$(PROJECT).ltx" >> generate_bit.tcl
	echo "write_hw_platform -fixed -force -include_bit $(PROJECT).xsa" >> generate_bit.tcl
	vivado -nojournal -nolog -mode batch -source generate_bit.tcl
	ln -f -s $(PROJECT).runs/impl_1/$(PROJECT).bit .
	ln -f -s $(PROJECT).runs/impl_1/$(PROJECT).bin .
	if [ -e $(PROJECT).runs/impl_1/$(PROJECT).ltx ]; then ln -f -s $(PROJECT).runs/impl_1/$(PROJECT).ltx .; fi
	mkdir -p rev
	COUNT=100; \
	while [ -e rev/$(PROJECT)_rev$$COUNT.bit ]; \
	do COUNT=$$((COUNT+1)); done; \
	cp -pv $(PROJECT).runs/impl_1/$(PROJECT).bit rev/$(PROJECT)_rev$$COUNT.bit; \
	cp -pv $(PROJECT).runs/impl_1/$(PROJECT).bin rev/$(PROJECT)_rev$$COUNT.bin; \	if [ -e $(PROJECT).runs/impl_1/$(PROJECT).ltx ]; then cp -pv $(PROJECT).runs/impl_1/$(PROJECT).ltx rev/$(PROJECT)_rev$$COUNT.ltx; fi; \
	cp -pv $(PROJECT).xsa rev/$(PROJECT)_rev$$COUNT.xsa;
