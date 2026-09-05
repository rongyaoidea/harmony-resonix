# resonix 包 —— 装入 Termony base.hnp
#
# 用法（在 Termony 仓库的 build-hnp/ 目录下）：
#   1. mkdir -p resonix && cp -r <本目录>/* resonix/
#   2. 把 engine/build-resonix.sh 产出的两个二进制放到 resonix/prebuilt/：
#        prebuilt/resonix      （可选：resonix 官方 CLI，若走 rootfs 则不需要）
#        prebuilt/bridge       （HTTP 桥 + Web UI 托管，rootfs 内运行）
#      或在 rootfs 部署模式下，bridge/resonix 直接放 rootfs，
#      本包只装 qemu-vroot 已有依赖（无需改动本包）。
#   3. 在 build-hnp/Makefile 的 PKGS 列表追加 "resonix"
#   4. make resonix && make base.hnp && make copy
#
# 说明：本包不做交叉编译——resonix/bridge 是纯 Go 静态二进制
#（GOOS=linux GOARCH=arm64 CGO_ENABLED=0），由 engine/build-resonix.sh
# 在任意 x86 构建机上产出，经 qemu-vroot/Alpine rootfs 运行（推荐），
# 或直接放 sysroot/bin 在 OHOS 宿主运行（实验性，musl 兼容性待验证）。

PRODUCT = bridge

all: install

prebuilt/$(PRODUCT):
	@echo "=============================================================="
	@echo " 缺少 prebuilt/$(PRODUCT)。请先在构建机执行："
	@echo "   cd engine && ./build-resonix.sh"
	@echo " 并把 engine/bridge/bin/bridge 拷到 hnp/resonix/prebuilt/bridge"
	@echo "=============================================================="
	@exit 1

install: prebuilt/$(PRODUCT)
	rm -rf build
	mkdir -p build/bin ../sysroot/bin
	cp prebuilt/$(PRODUCT) build/bin/$(PRODUCT)
	chmod 0755 build/bin/$(PRODUCT)
	# 同时复制一份到 sysroot（宿主直跑实验路径）；
	# rootfs 部署模式下此副本无害（qemu-vroot 优先用 rootfs 内版本）。
	cp -v build/bin/$(PRODUCT) ../sysroot/bin/$(PRODUCT)
	@echo "[resonix] installed to sysroot/bin/$(PRODUCT)"

clean:
	rm -rf build
