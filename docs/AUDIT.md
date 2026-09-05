# 代码审查与修复记录

针对 harmony-resonix v0.2 全量源码的审查，分类如下。
涉及文件：`engine/bridge/*`、`termony-patches/**`、`scripts/*`、`hnp/resonix/Makefile`。

## 已修复

### 1. [逻辑错误] index.html 重复的 `session/request_permission` 分支（死代码）
`index.html` 的 `ws.onmessage` 中 `else if (m.method === 'session/request_permission')`
被写了**两段完全相同的分支**（约第 127 行与第 147 行），第二段因 if/else-if 链
语义**永远不可达**。删除重复段，保留一段有效处理。

### 2. [逻辑错误] engine.cpp 参数不足时返回 `nullptr` → ArkTS 误判成功
`StartEngine` 在 `argc < 2` 时 `napi_throw_error` 后 `return nullptr`。ArkTS 侧
`const pid = testNapi.startEngine(...)` 收到 `undefined`，而 `undefined <= 0` 求值为
`false`，导致**把启动失败误判为成功**，空等 15s 探活后才报失败。
改为返回 `-1`（`napi_create_double`），使 `pid <= 0` 正确成立。

### 3. [功能缺陷] Index.ets Web 组件未配置 `onConfirm` → 审批原生框不弹
Web UI 用 `confirm()` 弹工具审批框，但 ArkWeb 默认不显示 JS 的 confirm——除非
Web 组件注册 `onConfirm` 回调并调用 `event.result.handleConfirm(true)`。原代码缺该
回调，审批对话框可能静默不弹、用户无法选择。
已在 Web 组件上补 `.onConfirm(...)` 回调。

### 4. [潜在 bug] 构建脚本用 `./cmd/...` 编译 resonix（会连带无关包失败）
`build-all.sh` 与 `build-resonix.sh` 用 `go build ./cmd/...` 编译 resonix CLI，
会把 `cmd/` 下全部包（含 `reasonix-launcher`、`e2ebench`、`signpath-contract` 等）
一并纳入；其中部分可能依赖 cgo/GUI，在 `CGO_ENABLED=0` 下编译失败，连带整条命令
失败。改为精确编译 `./cmd/reasonix`。

### 5. [潜在 bug] build-all.sh 缺 GOPROXY / GOFLAGS / GOROOT 处理
`build-all.sh` 直接 `go build` 编译 resonix，未设国内模块代理（海外/受限网络
拉不到依赖），也未处理构建机预置 `GOROOT` 指向旧版 Go 的污染（resonix go.mod
要求 1.26）。补上与 `build-resonix.sh` 一致的环境变量默认值 + 注释提示。

### 6. [潜在 bug] ws.go 缺帧大小上限（DoS）
`readFrame` 对客户端声明的帧长度 `length` 直接 `make([]byte, length)`，恶意/错误的
超大长度会导致 OOM 或 panic。新增 `maxFrameSize = 16MB` 上限检查，超限直接关闭连接。

### 7. [潜在 bug] main.go 仅杀单进程 → 引擎子进程树成孤儿
原 `handleWS` 的 `defer` 用 `s.cmd.Process.Kill()` 只杀 `/bin/sh -c` 父亲，而
`sh` 派生的 qemu-vroot/bridge 子进程不被清理，重连/切 Tab 会堆积孤儿进程。
改为：启动引擎时设 `Setpgid` 独立进程组，`killEngine()` 对 `-pgid` 发
`SIGTERM → SIGKILL` 整体清理；并存为进程级**单例**（新连接先清理旧引擎），
避免 WebView 重连风暴堆积引擎进程。

### 8. [潜在 bug] engine.cpp 子进程 dup2 后未 close 原 fd
`setsid` 后 `dup2(logfd, ...)` / `dup2(nullfd, ...)` 后原 fd 未关闭，会被 execv
继承到引擎进程，造成描述符泄漏。dup2 后立即 `close` 原 fd。

### 9. [潜在 bug] engine.cpp `EngineRunning` 退出后 `g_engine_pid` 不重置
`waitpid(..., WNOHANG)` 已 reap 退出进程时，`g_engine_pid` 仍保留脏值。补充分支：
`r > 0`（已退出并 reap）时重置为 `-1`，避免后续 `kill(g_engine_pid, 0)` 误判。

### 10. [假实现] 删除 `RegisterEngineNapi` 空壳
`engine.cpp` 中 `RegisterEngineNapi` 为空实现（仅 `(void)env;(void)exports;`），
真实注册走 `napi_init.cpp` 的 `desc[]` 属性表（已在 diff 文档与 apply 脚本中
正确插入 `engine_napi::{Start,Stop,EngineRunning}`，本次验证已确认）。删除空壳
及其在 `engine.h` 中的声明，消除误导性死代码。

### 11. [逻辑错误] Index.ets `onConfirm` 自动放行（二轮审查，2026-09 UI 调研时发现）
ArkWeb 官方文档明确：`onConfirm` 返回 `true` 后应用需**自行绘制弹窗**并应答
`JsResult`；此前实现直接 `handleConfirm(true)`——所有网页 `confirm()` 一律自动
确认，等于审批不审（且 `handleConfirm` 不接受布尔参数）。修复：改为
`getUIContext().showAlertDialog()`（取消/确定双键、`autoCancel:false`），异步
应答 `handleCancel()/handleConfirm()`。同时 Web UI 侧工具审批升级为应用内
自定义审批卡片，不再依赖 `confirm()`（详见 docs/RESEARCH.md §5）。

## 已确认无问题（不作为 bug）

- ws.go 分片重组、Ping/Pong、UTF-8 跨分片累积：逻辑正确。
- main.go 的 ACP 行分隔协议（`\n` 补尾）：此前已修复并回归通过。
- napi 注册与 `engine_napi` 命名空间一致（diff 用 `engine_napi::StartEngine` 限定名）。
- apply-termony-patches.sh 在真实 Termony 源码副本上五步验证通过。

## 验证

- `go build`（x86 + arm64）均通过。
- 端到端回归（`tests/test_e2e.py`）：initialize / session/new / session/prompt +
  `session/request_permission` 审批闭环全链路 PASS。
- 重连场景（自定义脚本）：断开→重连仍可 initialize+session/new；结束时无 mock
  引擎僵尸进程（进程组清理生效）。
- UI 渲染与交互（playwright 无头浏览器，390×844 手机视口）：浅色/深色主题、
  空状态 hero、建议 chips、消息气泡、**审批卡片弹出→允许→回显闭环**均截图验证通过。
