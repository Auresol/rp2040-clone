VERILATOR = verilator
RISCV_GCC = riscv64-unknown-elf-gcc
RISCV_OBJCOPY = riscv64-unknown-elf-objcopy

TOP      = rvsoc_top
RTL_DIR  = rtl
SIM_DIR  = sim

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
	--top-module $(TOP)

SRC_RTL = \
	$(RTL_DIR)/soc/$(TOP).sv

SIM_CPP = $(SIM_DIR)/main.cpp

SW_SRC  = $(SIM_DIR)/sw/hello.S
SW_ELF  = $(SIM_DIR)/sw/hello.elf
SW_BIN  = $(SIM_DIR)/sw/hello.bin

.PHONY: all sim sw clean

all: sim

sw: $(SW_BIN)

$(SW_ELF): $(SW_SRC)
	$(RISCV_GCC) -march=rv32imc -mabi=ilp32 -nostartfiles -nostdlib -Ttext=0x0 -o $@ $<

$(SW_BIN): $(SW_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

sim: sw
	$(VERILATOR) $(VERILATOR_FLAGS) $(SRC_RTL) $(SIM_CPP)
	./obj_dir/V$(TOP)

clean:
	rm -rf obj_dir $(SW_ELF) $(SW_BIN) dump.vcd
