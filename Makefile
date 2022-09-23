unexport CPATH
unexport C_INCLUDE_PATH
unexport CPLUS_INCLUDE_PATH
unexport PKG_CONFIG_PATH
unexport CMAKE_MODULE_PATH
unexport CCACHE_PATH
unexport LD_LIBRARY_PATH
unexport LD_RUN_PATH
unexport UNZIP

export LC_ALL = C
export CCACHE_DIR = $(HOME)/.cache/nanopi-r4s-kernel

BUILD_DIR     ?= /tmp/nanopi-r4s-kernel
DOWNLOAD_DIR  ?= $(CURDIR)/.dl
SOURCE_DIR    ?= $(CURDIR)/.src
CROSS_COMPILE ?= aarch64-none-linux-gnu-
LINUX_VERSION ?= 5.15.70

.PHONY: default
default: build

.PHONY: download
download:
ifeq ($(wildcard $(DOWNLOAD_DIR)/linux-$(LINUX_VERSION).tar.xz),)
	@wget -P $(DOWNLOAD_DIR) https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$(LINUX_VERSION).tar.xz
endif

.PHONY: extract
extract: download
ifeq ($(wildcard $(SOURCE_DIR)/linux/Makefile),)
	@mkdir -p $(SOURCE_DIR)/linux
	@tar -xvf $(DOWNLOAD_DIR)/linux-$(LINUX_VERSION).tar.xz -C $(SOURCE_DIR)/linux --strip-components=1
endif

.PHONY: defconfig
defconfig: extract
ifeq ($(wildcard $(BUILD_DIR)/linux/.config),)
	@$(MAKE) \
		-C $(SOURCE_DIR)/linux \
		-j $(shell nproc) \
		O=$(BUILD_DIR)/linux \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		CC="ccache $(CROSS_COMPILE)gcc" \
		CXX="ccache $(CROSS_COMPILE)g++" \
		KBUILD_BUILD_TIMESTAMP='' \
		defconfig
endif

.PHONY: menuconfig
menuconfig: defconfig
	@$(MAKE) \
		-C $(SOURCE_DIR)/linux \
		-j $(shell nproc) \
		O=$(BUILD_DIR)/linux \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		CC="ccache $(CROSS_COMPILE)gcc" \
		CXX="ccache $(CROSS_COMPILE)g++" \
		KBUILD_BUILD_TIMESTAMP='' \
		menuconfig

.PHONY: build
build: defconfig
	@$(MAKE) \
		-C $(SOURCE_DIR)/linux \
		-j $(shell nproc) \
		O=$(BUILD_DIR)/linux \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		CC="ccache $(CROSS_COMPILE)gcc" \
		CXX="ccache $(CROSS_COMPILE)g++" \
		KBUILD_BUILD_TIMESTAMP=''

.PHONY: clean
clean:
	@rm -fr $(BUILD_DIR)

.PHONY: distclean
distclean: clean
	@git clean -xdf $(SOURCE_DIR)
