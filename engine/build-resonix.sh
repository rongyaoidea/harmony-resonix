#!/usr/bin/env bash
# build-resonix.sh — 在任意 x86_64 Linux/macOS 构建机上交叉编译 resonix 引擎 + Web 桥
# 产物：aarch64 Linux 静态二进制（musl 兼容），供 Termony HNP / Alpine rootfs 使用
#
# 前置：
#   - Go >= 1.26.0（resonix go.mod 要求 toolchain go1.26.6；golang.google.cn/dl 下载）
#     ⚠️ 若构建机预置了 GOROOT 环境变量（指向旧版 Go），必须显式覆盖：
#        GOROOT=/opt/go1.26 PATH=/opt/go1.26/bin:$PATH ./build-resonix.sh
#     ⚠️ 国内网络建议保留默认 GOPROXY=goproxy.cn（脚本已内置，可用环境变量覆盖）
#     ⚠️ GitHub 直连克隆易断流，可走镜像：
#        git clone --depth 1 -b main-v2 \
#          https://ghproxy.net/https://github.com/esengine/DeepSeek-Reasonix.git \
#          engine/resonix-checkout
#   - 已确认全纯 Go（modernc.org/sqlite + charm.land 纯 Go 栈），CGO_ENABLED=0 可行
#   - site/ 前端已构建：cd engine/resonix-checkout/site && npm ci && npm run build
#     （构建产物目录见 astro.config.mjs 的 outDir，默认 dist/）
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/resonix-checkout"
OUT="$HERE/bridge/bin"
mkdir -p "$OUT"

export CGO_ENABLED=0
export GOOS=linux
export GOARCH=arm64
export GOFLAGS=-mod=mod
# 模块代理：默认走国内镜像（海外/CI 可 GOPROXY=https://proxy.golang.org,direct 覆盖）
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

echo "==> [1/2] 构建 bridge（HTTP 桥 + Web UI 托管）"
# bridge 嵌入 site/ 构建产物（见 bridge/main.go 的 //go:embed）
(cd "$HERE/bridge" && go build -trimpath -ldflags="-s -w" -o "$OUT/bridge" .)

echo "==> [2/2] （可选）构建 resonix CLI 本体（终端形态用；Web 形态可跳过）"
if [ -d "$SRC/cmd/reasonix" ] || [ -d "$SRC/cmd/resonix" ]; then
  (cd "$SRC" && go build -trimpath -ldflags="-s -w" -o "$OUT/reasonix" ./cmd/...) || {
    echo "    resonix CLI 构建失败（依赖/版本问题），Web 桥模式不受影响"; }
fi

echo "==> 产物："
ls -lh "$OUT"
file "$OUT/bridge" || true
echo "==> 完成。把 bridge 二进制放进 rootfs：/usr/local/bin/bridge"
