#!/usr/bin/env bash
# apply-termony-patches.sh — 把 harmony-resonix 的改造应用到 Termony 工程副本
#
# 用法：
#   git clone --depth 1 https://github.com/FunBocchi/Termony.git termony
#   ./apply-termony-patches.sh /path/to/termony
#
# 改动全部为“新增文件 + 显式小改”，不动 Termony 既有逻辑（详见各文件头注释）。
set -euo pipefail

TARGET="${1:?用法: apply-termony-patches.sh /path/to/termony}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

test -f "$TARGET/entry/src/main/cpp/napi_init.cpp" || { echo "不是 Termony 工程: $TARGET"; exit 1; }

echo "==> [1/5] 新增 engine.h / engine.cpp（引擎进程管理，零侵入）"
cp -v "$HERE/termony-patches/cpp/engine.h"  "$TARGET/entry/src/main/cpp/engine.h"
cp -v "$HERE/termony-patches/cpp/engine.cpp" "$TARGET/entry/src/main/cpp/engine.cpp"

echo "==> [2/5] CMakeLists.txt 追加 engine.cpp"
CMAKE="$TARGET/entry/src/main/cpp/CMakeLists.txt"
grep -q "engine.cpp" "$CMAKE" || \
  sed -i 's/add_library(entry SHARED napi_init.cpp terminal.cpp)/add_library(entry SHARED napi_init.cpp terminal.cpp engine.cpp)/' "$CMAKE" || true
grep -n "engine.cpp" "$CMAKE" || { echo "  !! 未自动插入，请手动把 engine.cpp 加入 add_library(entry ...) 源列表"; }

echo "==> [3/5] napi_init.cpp 注册 startEngine/stopEngine/engineRunning"
NAPI="$TARGET/entry/src/main/cpp/napi_init.cpp"
grep -q '#include "engine.h"' "$NAPI" || \
  sed -i 's|#include "terminal.h"|#include "terminal.h"\n#include "engine.h"|' "$NAPI"
grep -q '"startEngine"' "$NAPI" || \
  sed -i 's|{"pushPaste", nullptr, PushPaste, nullptr, nullptr, nullptr, napi_default, nullptr},|{"pushPaste", nullptr, PushPaste, nullptr, nullptr, nullptr, napi_default, nullptr},\n        {"startEngine", nullptr, engine_napi::StartEngine, nullptr, nullptr, nullptr, napi_default, nullptr},\n        {"stopEngine", nullptr, engine_napi::StopEngine, nullptr, nullptr, nullptr, napi_default, nullptr},\n        {"engineRunning", nullptr, engine_napi::EngineRunning, nullptr, nullptr, nullptr, napi_default, nullptr},|' "$NAPI"
grep -n "startEngine" "$NAPI" || { echo "  !! 注册失败，请对照 termony-patches/cpp/napi_init.cpp.diff 手工插入"; }

echo "==> [4/5] 替换前端 Index.ets（Tabs: Agent WebView + Terminal）"
cp -v "$HERE/termony-patches/ets/pages/Index.ets" "$TARGET/entry/src/main/ets/pages/Index.ets"

echo "==> [5/5] 检查 deviceTypes（Termony 默认 2in1；手机支持随 Termony 上游解锁）"
grep -n "deviceTypes" -A 2 "$TARGET/entry/src/main/module.json5" | head -4

cat <<'EOF'

完成。后续：
  1. DevEco Studio 打开 termony 工程 → 配置签名 → Build HAP
  2. 按 docs/DEPLOY.md 部署 rootfs + bridge
  3. （可选）hnp/resonix 挂进 build-hnp 打进 base.hnp
EOF
