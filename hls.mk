CMAKE ?= cmake
BUILD_DIR := build
LIB_DIR := $(BUILD_DIR)/lib

.PHONY: ip clean

ip: $(LIB_DIR)/Makefile
	$(MAKE) ip -C $(LIB_DIR)

$(LIB_DIR)/Makefile:
	mkdir -p $(LIB_DIR)
	cd $(LIB_DIR) && $(CMAKE) $(CMAKE_ARGS) $(abspath lib/fpga-network-stack)

clean_ip:
	rm -rf $(BUILD_DIR)
