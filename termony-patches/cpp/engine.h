// engine.h — resonix-harmony 引擎进程管理（新增，零侵入 Termony 原有 terminal.cpp）
//
// 职责：在鸿蒙应用沙箱内以独立会话（setsid）拉起后台引擎进程
//（如 qemu-vroot → Alpine rootfs → resonix/bridge），并可探活/终止。
// 不创建 PTY、不做终端渲染 —— 图形交互全部交给 ArkTS WebView 层。
#ifndef ENGINE_H
#define ENGINE_H

#include <napi/native_api.h>

namespace engine_napi {

// StartEngine(cmd: string, args: string[], envPairs: string[], cwd: string) -> number(pid)
//   - cmd        引擎可执行文件绝对路径（如 /data/app/bin/qemu-vroot-aarch64）
//   - args       参数数组（含 -E PATH=... -L rootfs 等与引擎二进制路径）
//   - envPairs   额外环境变量，形如 ["KEY=VALUE", ...]
//   - cwd        工作目录（默认 /storage/Users/currentUser）
// stdout/stderr 追加重定向到 <filesDir>/engine.log，stdin 挂 /dev/null。
napi_value StartEngine(napi_env env, napi_callback_info info);

// StopEngine() -> boolean  终止最近一次 StartEngine 拉起的进程组（SIGTERM → SIGKILL 兜底）
napi_value StopEngine(napi_env env, napi_callback_info info);

// EngineRunning() -> boolean  探活（waitpid WNOHANG，非阻塞）
napi_value EngineRunning(napi_env env, napi_callback_info info);

} // namespace engine_napi

// 注册到 libentry.so 的辅助入口（在 napi_init.cpp 的 Init 阶段调用）
void RegisterEngineNapi(napi_env env, napi_value exports);

#endif // ENGINE_H
