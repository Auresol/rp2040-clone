VERILATOR    = verilator
RISCV_GCC     ?= riscv64-unknown-elf-gcc
RISCV_OBJCOPY ?= riscv64-unknown-elf-objcopy

TOP      = rvsoc_top
RTL_DIR  = rtl
TB_DIR   = sim/tb
SW_DIR   = sim/sw

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
SIM_CPP  = $(TB_DIR)/main.cpp
SIM_BIN  = obj_dir/V$(TOP)

# All SystemVerilog sources — simulator rebuilds when any .sv changes.
RTL_SRCS = $(shell find $(RTL_DIR) -name "*.sv")

GCC_FLAGS = -march=rv32imc_zicsr -mabi=ilp32 -nostartfiles -nostdlib -Ttext=0x0

TESTS = hello test_alu test_mem test_branch test_gpio test_pio test_uart
SW_BINS = $(addprefix $(SW_DIR)/, $(addsuffix .bin, $(TESTS)))

# ---------------------------------------------------------------------------
# Unit testbenches (standalone, no SoC)

ARB_RTL = $(RTL_DIR)/soc/fabric/ahb_arbiter.sv
ARB_BIN = obj_dir_arb/Vahb_arbiter

$(ARB_BIN): $(ARB_RTL) $(TB_DIR)/tb_arbiter.cpp
	$(VERILATOR) --cc --exe --build -Wno-fatal \
		--top-module ahb_arbiter \
		-Mdir obj_dir_arb \
		$(ARB_RTL) $(TB_DIR)/tb_arbiter.cpp

test-arbiter: $(ARB_BIN)
	./$(ARB_BIN)

DEC_RTL = $(RTL_DIR)/soc/fabric/ahb_decoder.sv
DEC_BIN = obj_dir_dec/Vahb_decoder

$(DEC_BIN): $(DEC_RTL) $(TB_DIR)/tb_decoder.cpp
	$(VERILATOR) --cc --exe --build -Wno-fatal \
		--top-module ahb_decoder \
		-Mdir obj_dir_dec \
		$(DEC_RTL) $(TB_DIR)/tb_decoder.cpp

test-decoder: $(DEC_BIN)
	./$(DEC_BIN)

# ---------------------------------------------------------------------------

.PHONY: all sim test sw clean remote-test test-arbiter test-decoder

all: sim

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
	./$(SIM_BIN) $(SW_DIR)/hello.bin

# Run all tests
test: $(SIM_BIN) $(SW_BINS)
	@passed=0; failed=0; \
	for t in $(TESTS); do \
		if ./$(SIM_BIN) $(SW_DIR)/$$t.bin; then \
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
	rm -rf obj_dir* $(SW_DIR)/*.elf $(SW_DIR)/*.bin

# ---------------------------------------------------------------------------
# Remote test machine

REMOTE_HOST = pc-nixos
REMOTE_PATH = /data/rp2040-clone

remote-test:
	rsync -av --delete \
		--exclude='.git' \
		--exclude='obj_dir*' \
		--exclude='$(SW_DIR)/*.elf' \
		--exclude='$(SW_DIR)/waveform/*.vcd' \
		--exclude='$(SW_DIR)/*.bin' \
		. $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); env VERILATOR_ROOT=(verilator --getenv VERILATOR_ROOT) RISCV_GCC=(which riscv64-none-elf-gcc | get path | first) RISCV_OBJCOPY=(which riscv64-none-elf-objcopy | get path | first) make test"
