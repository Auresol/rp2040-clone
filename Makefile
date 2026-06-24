VERILATOR    = verilator
RISCV_GCC     ?= riscv64-unknown-elf-gcc
RISCV_OBJCOPY ?= riscv64-unknown-elf-objcopy

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

FW_TESTS  = test_c_hello test_c_launch test_dualcore
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

.PHONY: all sim test sw clean remote-test remote-hello test-arbiter test-decoder hello

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

remote-test:
	rsync -av --delete \
		--exclude='.git' \
		--exclude='obj_dir' \
		--exclude='$(SW_DIR)/*.elf' \
		--exclude='$(SW_DIR)/*.bin' \
		--exclude='$(SW_DIR)/waveform/*.vcd' \
		. $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); env VERILATOR_ROOT=(verilator --getenv VERILATOR_ROOT) RISCV_GCC=(which riscv64-none-elf-gcc | get path | first) RISCV_OBJCOPY=(which riscv64-none-elf-objcopy | get path | first) make test"

remote-hello:
	rsync -av --delete \
		--exclude='.git' \
		--exclude='obj_dir' \
		--exclude='$(SW_DIR)/*.elf' \
		--exclude='$(SW_DIR)/*.bin' \
		--exclude='$(SW_DIR)/waveform' \
		. $(REMOTE_HOST):$(REMOTE_PATH)
	ssh $(REMOTE_HOST) "cd $(REMOTE_PATH); \
		mkdir $(SW_DIR)/waveform; \
		env VERILATOR_ROOT=(verilator --getenv VERILATOR_ROOT) RISCV_GCC=(which riscv64-none-elf-gcc | get path | first) RISCV_OBJCOPY=(which riscv64-none-elf-objcopy | get path | first) make hello; \
		vcd2fst $(SW_DIR)/waveform/hello.vcd $(SW_DIR)/waveform/compress_hello.fst"
	mkdir $(SW_DIR)/waveform
	scp $(REMOTE_HOST):$(REMOTE_PATH)/$(SW_DIR)/waveform/compress_hello.fst \
		$(SW_DIR)/waveform/compress_hello.fst
