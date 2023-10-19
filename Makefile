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

BASE_DIR       ?= /tmp/nanopi-r4s-kernel
BUILD_DIR      ?= $(BASE_DIR)/build
SOURCE_DIR     ?= $(BASE_DIR)/source
DISTRIB_DIR    ?= $(BASE_DIR)/distrib
DOWNLOAD_DIR   ?= $(CURDIR)/.dl
CROSS_COMPILE  ?= aarch64-linux-gnu-
LINUX_VERSION  ?= 6.1.55
LINUX_MAJOR    ?= $(basename $(basename $(LINUX_VERSION)))
UBUNTU_RELEASE ?= jammy

.PHONY: default
default: initrd

.PHONY: download
download:
ifeq ($(wildcard $(DOWNLOAD_DIR)/linux-$(LINUX_VERSION).tar.xz),)
	@wget -P $(DOWNLOAD_DIR) https://cdn.kernel.org/pub/linux/kernel/v$(LINUX_MAJOR).x/linux-$(LINUX_VERSION).tar.xz
endif
ifeq ($(wildcard $(DOWNLOAD_DIR)/$(UBUNTU_RELEASE)-base-arm64.tar.gz),)
	@wget -P $(DOWNLOAD_DIR) http://cdimage.ubuntu.com/ubuntu-base/$(UBUNTU_RELEASE)/daily/current/$(UBUNTU_RELEASE)-base-arm64.tar.gz
endif

.PHONY: extract
extract: download
ifeq ($(wildcard $(SOURCE_DIR)/linux),)
	@mkdir -p $(SOURCE_DIR)/linux
	@tar -xvf $(DOWNLOAD_DIR)/linux-$(LINUX_VERSION).tar.xz -C $(SOURCE_DIR)/linux --strip-components=1
endif
ifeq ($(wildcard $(DISTRIB_DIR)),)
	@mkdir -p $(DISTRIB_DIR)/rootfs
	@sudo tar -xvf $(DOWNLOAD_DIR)/$(UBUNTU_RELEASE)-base-arm64.tar.gz -C $(DISTRIB_DIR)/rootfs
endif

.PHONY: patch
patch: extract
ifeq ($(wildcard $(SOURCE_DIR)/linux/arch/arm64/configs/nanopi4_linux_defconfig),)
	@patch -d $(SOURCE_DIR)/linux -p 1 -i $(CURDIR)/friendlyarm-kernel-rockchip-nanopi-r2-v6.1.y.patch
endif

.PHONY: defconfig
defconfig: patch
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
		nanopi4_linux_defconfig
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

.PHONY: install
install: build
	@mkdir -p $(BUILD_DIR)/boot/dtbs
	@$(MAKE) \
		-C $(SOURCE_DIR)/linux \
		-j $(shell nproc) \
		O=$(BUILD_DIR)/linux \
		ARCH=arm64 \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		CC="ccache $(CROSS_COMPILE)gcc" \
		CXX="ccache $(CROSS_COMPILE)g++" \
		KBUILD_BUILD_TIMESTAMP='' \
		INSTALL_MOD_PATH=$(BUILD_DIR)/modules \
		INSTALL_HDR_PATH=$(BUILD_DIR)/headers \
		INSTALL_DTBS_PATH=$(BUILD_DIR)/boot/dtbs \
		INSTALL_PATH=$(BUILD_DIR)/boot \
		zinstall modules_install headers_install dtbs_install
	@rm $(BUILD_DIR)/modules/lib/modules/$(LINUX_VERSION)/build
	@rm $(BUILD_DIR)/modules/lib/modules/$(LINUX_VERSION)/source

.PHONY: rootfs
rootfs: install
	@echo "nameserver 127.0.0.53" | sudo tee $(DISTRIB_DIR)/rootfs/etc/resolv.conf
	@sudo mount -t devtmpfs devtmpfs $(DISTRIB_DIR)/rootfs/dev
	@sudo mount -t devpts devpts $(DISTRIB_DIR)/rootfs/dev/pts
	@sudo mount -t proc proc $(DISTRIB_DIR)/rootfs/proc
	@sudo mount -t tmpfs tmpfs $(DISTRIB_DIR)/rootfs/run
	@sudo mount -t sysfs sysfs $(DISTRIB_DIR)/rootfs/sys
	@sudo mount -t tmpfs tmpfs $(DISTRIB_DIR)/rootfs/tmp
	@sudo chroot $(DISTRIB_DIR)/rootfs apt update
	@sudo chroot $(DISTRIB_DIR)/rootfs apt install -y --no-install-recommends openssh-server
	@sudo rm -rf $(DISTRIB_DIR)/rootfs/var/lib/apt/lists/*
	@awk '{print $$2}' /proc/mounts | grep -s "$(DISTRIB_DIR)/rootfs" | sort -r | xargs --no-run-if-empty sudo umount

.PHONY: initrd
initrd: rootfs
	@cd $(DISTRIB_DIR)/rootfs && sudo find . -type f -print | sudo cpio -ov | pixz > $(DISTRIB_DIR)/rootfs.cpio.xz

.PHONY: clean
clean:
	@awk '{print $$2}' /proc/mounts | grep -s "$(DISTRIB_DIR)/rootfs" | sort -r | xargs --no-run-if-empty sudo umount
	@sudo rm -fr $(BASE_DIR)
