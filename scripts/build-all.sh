#!/usr/bin/env bash
# build-all.sh — 一键构建链：bridge → （可选 resonix CLI）→ 应用 Termony 补丁 → 提示打包
#
#   ./build-all.sh [--with-resonix]
#
#   --with-resonix  同时从上游源码交叉编译 resonix CLI（需要 engine/resonix-checkout
#                   已 clone；Web 桥模式可不编，rootfs 内仅需 bridge）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
export CGO_ENABLED=0 GOOS=linux GOARCH=arm64
# resonix 依赖现代 Go 栈（go.mod 要求 1.26）；构建机若预置 GOROOT 指向旧版 Go 需显式覆盖：
#   GOROOT=/opt/go1.26 PATH=/opt/go1.26/bin:$PATH ./build-all.sh
export GOROOT="${GOROOT:-$(go env GOROOT)}"
# 国内/受限网络走镜像（海外 CI 可用 GOPROXY=https://proxy.golang.org,direct 覆盖）
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOFLAGS="${GOFLAGS:--mod=mod}"

echo "==> [1/3] bridge（ACP↔WS 桥 + 内嵌 Web UI）"
(cd "$HERE/engine/bridge" && go build -trimpath -ldflags="-s -w" -o bin/bridge .)
ls -lh "$HERE/engine/bridge/bin/bridge"

if [ "${1:-}" = "--with-resonix" ]; then
  echo "==> [2/3] resonix CLI（上游源码）"
  SRC="$HERE/engine/resonix-checkout"
  test -f "$SRC/go.mod" || { echo "缺少 $SRC —— 先 git clone 上游（见 README 快速开始）"; exit 1; }
  (cd "$SRC" && go build -trimpath -ldflags="-s -w" -o "$HERE/engine/bridge/bin/reasonix" ./cmd/reasonix)
  ls -lh "$HERE/engine/bridge/bin/reasonix" || true
else
  echo "==> [2/3] 跳过 resonix CLI（--with-resonix 可开启）"
fi

echo "==> [3/3] Termony 改造应用（需先 clone Termony 并作为参数）"
echo "    ./scripts/apply-termony-patches.sh /path/to/termony"
echo
echo "构建产物：engine/bridge/bin/  （bridge → rootfs /usr/local/bin/bridge）"
echo "下一步见 docs/DEPLOY.md"
