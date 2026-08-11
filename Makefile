VERILATOR    = verilator
RISCV_GCC     ?= riscv64-unknown-elf-gcc
RISCV_OBJCOPY ?= riscv64-unknown-elf-objcopy
VIVADO        ?= /tools/xillinx/2025.2/Vivado/bin/vivado

TOP      = rvsoc_top
RTL_DIR  = rtl
SIM_DIR  = sim
SW_DIR   = $(SIM_DIR)/sw

HAZARD3_HDL = $(RTL_DIR)/core/hazard3/hdl

VERILATOR_FLAGS = \
	--cc \
	--exe \
	--build \
	--trace \
	-Wno-fatal \
	--public-flat-rw \
	-I$(HAZARD3_HDL) \
	-y $(HAZARD3_HDL)/arith \
	-y $(RTL_DIR)/soc/fabric \
	-y $(RTL_DIR)/soc/memory \
	-y $(RTL_DIR)/soc/peripheral \
	-y $(RTL_DIR)/soc/peripheral/pio \
	--top-module $(TOP)
	
SRC_RTL  = $(RTL_DIR)/soc/$(TOP).sv
SIM_CPP  = $(SIM_DIR)/main.cpp
SIM_BIN  = obj_dir/V$(TOP)

# All SystemVerilog sources — simulator rebuilds when any .sv changes.
RTL_SRCS = $(shell find $(RTL_DIR) -name "*.sv")

GCC_FLAGS = -march=rv32imc_zicsr -mabi=ilp32 -nostartfiles -nostdlib -Ttext=0x0

# C firmware (uses crt0.S + link.ld instead of raw -Ttext=0x0)
FW_DIR    = fw
FW_FLAGS  = -march=rv32imc_zicsr -mabi=ilp32 -nostartfiles -nostdlib \
            -T $(FW_DIR)/link.ld -I$(FW_DIR) -O1

FW_TESTS  = test_c_hello test_c_pio test_c_pio_gpio
FW_BINS   = $(addprefix $(SW_DIR)/, $(addsuffix .bin, $(FW_TESTS)))

$(SW_DIR)/%.bin: $(FW_DIR)/%.c $(FW_DIR)/crt0.S $(FW_DIR)/link.ld $(FW_DIR)/soc.h
	$(RISCV_GCC) $(FW_FLAGS) -o $(SW_DIR)/$*.elf $(FW_DIR)/crt0.S $<
	$(RISCV_OBJCOPY) -O binary $(SW_DIR)/$*.elf $(SW_DIR)/$*.bin
	rm -f $(SW_DIR)/$*.elf

TESTS = hello test_alu test_mem test_branch test_gpio test_pio
SW_BINS = $(addprefix $(SW_DIR)/, $(addsuffix .bin, $(TESTS)))

ARB_RTL = $(RTL_DIR)/soc/fabric/ahb_arbiter.sv
ARB_BIN = obj_dir_arb/Vahb_arbiter

$(ARB_BIN): $(ARB_RTL) $(SIM_DIR)/tb_arbiter.cpp
	$(VERILATOR) --cc --exe --build -Wno-fatal \
		--top-module ahb_arbiter \
		-Mdir obj_dir_arb \
		$(ARB_RTL) $(SIM_DIR)/tb_arbiter.cpp

test-arbiter: $(ARB_BIN)
	./$(ARB_BIN)

DEC_RTL = $(RTL_DIR)/soc/fabric/ahb_decoder.sv
DEC_BIN = obj_dir_dec/Vahb_decoder

$(DEC_BIN): $(DEC_RTL) $(SIM_DIR)/tb_decoder.cpp
	$(VERILATOR) --cc --exe --build -Wno-fatal \
		--top-module ahb_decoder \
		-Mdir obj_dir_dec \
		$(DEC_RTL) $(SIM_DIR)/tb_decoder.cpp

test-decoder: $(DEC_BIN)
	./$(DEC_BIN)

.PHONY: all sim test sw clean remote-test remote-hello test-arbiter test-decoder hello remote-fpga fpga-reports remote-fpga-kr260 fpga-reports-kr260 remote-bitstream-kr260

all: sim

hello: $(SIM_BIN) $(SW_DIR)/hello.bin
	mkdir -p $(SW_DIR)/waveform
	./$(SIM_BIN) $(SW_DIR)/hello.bin $(SW_DIR)/waveform/hello.vcd

# Build the simulator (recompiles when any .sv or the sim driver changes)
$(SIM_BIN): $(RTL_SRCS) $(SIM_CPP)
	$(VERILATOR) $(VERILATOR_FLAGS) $(SRC_RTL) $(SIM_CPP)

# Generic rules: .S -> .elf -> .bin
$(SW_DIR)/%.elf: $(SW_DIR)/%.S
	$(RISCV_GCC) $(GCC_FLAGS) -o $@ $<

$(SW_DIR)/%.bin: $(SW_DIR)/%.elf
	$(RISCV_OBJCOPY) -O binary $< $@

# Run just the sentinel smoke test
sim: $(SIM_BIN) $(SW_DIR)/hello.bin
	./$(SIM_BIN) $(SW_DIR)/hello.bin $(SW_DIR)/waveform/hello.vcd

# Run all tests (asm + C firmware)
test: $(SIM_BIN) $(SW_BINS) $(FW_BINS)
	@passed=0; failed=0; \
	for t in $(TESTS) $(FW_TESTS); do \
		if ./$(SIM_BIN) $(SW_DIR)/$$t.bin $(SW_DIR)/waveform/$$t.vcd; then \
			passed=$$((passed+1)); \
		else \
			failed=$$((failed+1)); \
		fi; \
	done; \
	echo ""; \
	echo "$$passed/$$((passed+failed)) tests passed"; \
	[ $$failed -eq 0 ]

sw: $(SW_BINS)

clean:
	rm -rf obj_dir $(SW_DIR)/*.elf $(SW_DIR)/*.bin $(SW_DIR)/*.vcd

# Remote test machine
REMOTE_HOST = pc-nixos
REMOTE_PATH = /data/rp2040-clone

RSYNC_EXCLUDES = \
	--exclude='.git' \
	--exclude='obj_dir' \
	--exclude='fpga/vivado' \
	--exclude='fpga/vivado_kr260' \
	--exclude='fpga/reports' \
	--exclude='fpga/reports_kr260' \
	--exclude='fpga/bitstream' \
	--exclude='$(SW_DIR)/*.elf' \
	--exclude='$(SW_DIR)/*.bin' \
	--exclude='$(SW_DIR)/waveform/*.vcd' \
	--exclude='*.log' \
	--exclude='*.jou'

remote-test:
	rsync -av --delete $(RSYNC_EXCLUDES) . $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); env VERILATOR_ROOT=(verilator --getenv VERILATOR_ROOT) RISCV_GCC=(which riscv64-none-elf-gcc | get path | first) RISCV_OBJCOPY=(which riscv64-none-elf-objcopy | get path | first) make test"

remote-hello:
	rsync -av --delete $(RSYNC_EXCLUDES) --exclude='$(SW_DIR)/waveform' . $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); \
		mkdir $(SW_DIR)/waveform; \
		env VERILATOR_ROOT=(verilator --getenv VERILATOR_ROOT) RISCV_GCC=(which riscv64-none-elf-gcc | get path | first) RISCV_OBJCOPY=(which riscv64-none-elf-objcopy | get path | first) make hello; \
		vcd2fst $(SW_DIR)/waveform/hello.vcd $(SW_DIR)/waveform/compress_hello.fst"
	mkdir $(SW_DIR)/waveform
	scp $(REMOTE_HOST):$(REMOTE_PATH)/$(SW_DIR)/waveform/compress_hello.fst \
		$(SW_DIR)/waveform/compress_hello.fst

# FPGA synthesis + implementation on remote, copy reports back
FPGA_REPORTS_DIR = fpga/reports

remote-fpga:
	rsync -av --delete $(RSYNC_EXCLUDES) . $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); distrobox-enter -n ubuntu22 -- $(VIVADO) -mode batch -source fpga/create_project.tcl"
	$(MAKE) fpga-reports

fpga-reports:
	mkdir -p $(FPGA_REPORTS_DIR)
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado/utilization_synth.rpt      $(FPGA_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado/utilization_synth_hier.rpt $(FPGA_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado/utilization_impl.rpt       $(FPGA_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado/utilization_impl_hier.rpt  $(FPGA_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado/timing.rpt                 $(FPGA_REPORTS_DIR)/ || true
	@echo "Reports copied to $(FPGA_REPORTS_DIR)/"

FPGA_KR260_REPORTS_DIR = fpga/reports_kr260

remote-fpga-kr260:
	rsync -av --delete $(RSYNC_EXCLUDES) --exclude='fpga/vivado_kr260' . $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); distrobox-enter -n ubuntu22 -- $(VIVADO) -mode batch -source fpga/create_project_kr260.tcl"
	$(MAKE) fpga-reports-kr260

fpga-reports-kr260:
	mkdir -p $(FPGA_KR260_REPORTS_DIR)
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado_kr260/utilization_synth.rpt      $(FPGA_KR260_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado_kr260/utilization_synth_hier.rpt $(FPGA_KR260_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado_kr260/utilization_impl.rpt       $(FPGA_KR260_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado_kr260/utilization_impl_hier.rpt  $(FPGA_KR260_REPORTS_DIR)/ || true
	scp $(REMOTE_HOST):$(REMOTE_PATH)/fpga/vivado_kr260/timing.rpt                 $(FPGA_KR260_REPORTS_DIR)/ || true
	@echo "Reports copied to $(FPGA_KR260_REPORTS_DIR)/"

# Bitstream: convert .bit → .bit.bin on pc-nixos, then scp here
BITSTREAM_DIR    = fpga/bitstream
KR260_BIT_REMOTE = $(REMOTE_PATH)/fpga/vivado_kr260/rvsoc_kr260.runs/impl_1/fpga_top_kr260.bit
BOOTGEN          = /tools/xillinx/2025.2/Vivado/bin/bootgen

remote-bitstream-kr260:
	mkdir -p $(BITSTREAM_DIR)
	ssh $(REMOTE_HOST) "cd /tmp; cp $(KR260_BIT_REMOTE) fpga_top.bit; cp $(REMOTE_PATH)/fpga/kr260.bif .; distrobox-enter -n ubuntu22 -- $(BOOTGEN) -image kr260.bif -arch zynqmp -o fpga_top.bit.bin -w on"
	scp $(REMOTE_HOST):/tmp/fpga_top.bit.bin $(BITSTREAM_DIR)/
	@echo "Bitstream ready at $(BITSTREAM_DIR)/fpga_top.bit.bin"
	@echo "To load on KR260:"
	@echo "  scp $(BITSTREAM_DIR)/fpga_top.bit.bin ubuntu@<board-ip>:/lib/firmware/"
	@echo "  ssh ubuntu@<board-ip> 'echo 0 > /sys/class/fpga_manager/fpga0/flags && echo fpga_top.bit.bin > /sys/class/fpga_manager/fpga0/firmware'"
