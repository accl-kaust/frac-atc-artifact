CMAKE ?= cmake
BUILD_DIR := build
LIB_DIR := $(BUILD_DIR)/lib

.PHONY: ip clean

ip: $(LIB_DIR)/Makefile
	$(MAKE) ip -C $(LIB_DIR)

$(LIB_DIR)/Makefile:
	mkdir -p $(LIB_DIR)
	cd $(LIB_DIR) && $(CMAKE) $(abspath lib/fpga-network-stack)

clean:
	rm -rf $(BUILD_DIR)
