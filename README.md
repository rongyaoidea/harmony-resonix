# harmony-resonix

**DeepSeek-Reasonix 编程引擎上鸿蒙 —— Termony 运行时 + resonix 引擎 + ArkTS WebView 前端。**

> 让开源 AI coding agent [DeepSeek-Reasonix](https://github.com/esengine/DeepSeek-Reasonix)（35k★，MIT）
> 以**本机进程**运行在 HarmonyOS 设备上，配原生 ArkTS 图形前端。
> 运行时底座复用 [Termony](https://github.com/FunBocchi/Termony)（MIT，"Termux for HarmonyOS"）已验证的
> HNP + qemu-vroot/Alpine rootfs 机制。

```
┌──────────────────────── HarmonyOS (2in1 / PC) ────────────────────────┐
│                                                                      │
│  ArkTS 前端 (Termony fork)                                           │
│  ┌──────────────────────┐  ┌───────────────────────────┐             │
│  │ Tab: Agent           │  │ Tab: Terminal             │             │
│  │ Web 组件             │  │ 原 Termony 终端           │             │
│  │ http://127.0.0.1:8080│  │ (alacritty C++/PTY)       │             │
│  └──────────┬───────────┘  └───────────────────────────┘             │
│             │ WebSocket / JSON-RPC (ACP)                             │
│  ┌──────────▼───────────────────────────────────────────┐             │
│  │ engine.cpp (NAPI): startEngine/stopEngine/engineRunning            │
│  └──────────┬───────────────────────────────────────────┘             │
│             │ fork+setsid+execv                                       │
│  ┌──────────▼───────────────────────────────────────────┐             │
│  │ qemu-vroot-aarch64（用户态 proot 模拟，无独立网络栈）  │             │
│  │   └── Alpine rootfs                                  │             │
│  │        ├── /usr/local/bin/bridge   (Go 静态, 4.4MB)  │             │
│  │        │     ├── HTTP :8080（healthz/Web UI/WS）     │             │
│  │        │     └── spawn /usr/local/bin/reasonix --acp │             │
│  │        └── /usr/local/bin/reasonix (Go 静态, 上游)   │             │
│  └──────────────────────────────────────────────────────┘             │
└──────────────────────────────────────────────────────────────────────┘
```

## 仓库结构

```
harmony-resonix/
├── termony-patches/          # 对 Termony 的三处改造（全部"新增+小改"，零侵入）
│   ├── cpp/engine.h|cpp      #   新增：引擎进程管理（fork+setsid+execv，日志重定向）
│   ├── cpp/napi_init.cpp.diff#   注册 startEngine/stopEngine/engineRunning
│   └── ets/pages/Index.ets   #   前端重构：Tabs [Agent(Web) | Terminal(原样保留)]
├── engine/
│   ├── bridge/main.go|ws.go  # HTTP 桥：ACP(stdio) ↔ WebSocket + 内嵌 Web UI（零依赖）
│   ├── bridge/index.html     #   ACP 客户端最小聊天 UI（go:embed 进二进制）
│   └── build-resonix.sh      # 交叉编译脚本（arm64 静态 ELF）
├── hnp/resonix/Makefile      # 可选：把 bridge 挂进 Termony base.hnp
├── scripts/apply-termony-patches.sh  # 一键把改造应用到 Termony 工程副本
├── docs/DEPLOY.md            # rootfs 部署 / ACP 校准 / 打包 HNP 全流程
├── LICENSE                   # 本项目 MIT
└── THIRD_PARTY_LICENSES.md   # resonix MIT / Termony MIT / qemu GPL 说明
```

## 快速开始

```sh
# 0) 拉源码
git clone --depth 1 https://github.com/FunBocchi/Termony.git termony
git clone --depth 1 -b main-v2 https://github.com/esengine/DeepSeek-Reasonix.git \
  harmony-resonix/engine/resonix-checkout

# 1) 构建 bridge（任意 x86 构建机，零依赖）
cd harmony-resonix/engine/bridge
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o bin/bridge .
# （Go 版本以 resonix go.mod 为准；bridge 自身 1.21 即可）

# 2) 应用改造
cd ../.. && ./scripts/apply-termony-patches.sh ../termony

# 3) DevEco Studio 打开 termony → 签名 → Build HAP → 装到鸿蒙设备

# 4) 部署 rootfs + bridge（Terminal Tab 里手动，详见 docs/DEPLOY.md）
#    alpine rootfs → <filesDir>/alpine_rootfs
#    bridge       → <rootfs>/usr/local/bin/bridge

# 5) 切到 Agent Tab —— 自动 startEngine → 探活 → 加载 Web UI
```

## 设计决策

| 决策 | 理由 |
|---|---|
| 引擎跑在 qemu-vroot/Alpine rootfs | Termony 已验证路径；纯静态 Go 二进制 100% 兼容 musl；用户态模拟无独立网络栈 → localhost 宿主直连，WebView 零配置 |
| bridge 单文件零依赖（自实现 RFC6455 服务端子集） | 构建机无需拉第三方 Go 依赖，离线可编；已冒烟验证 WS 握手/掩码/透传 |
| ACP（JSON-RPC over stdio）作为引擎接口 | resonix 官方支持 ACP（子命令 `reasonix acp`）；bridge 只做透传，协议演进不锁死；`--acp-cmd` 可配。**注意：行分隔 JSON，bridge 已保证每条消息以 `\n` 结尾写入引擎 stdin**；已通过 mock ACP 端到端测试（initialize / session/new / session/prompt + session/update 推送） |
| C++ 改动零侵入（新增 engine.cpp，不改 terminal.cpp） | 便于跟随 Termony 上游更新（rebase 成本≈0） |
| 前端保留 Terminal Tab | rootfs 部署/排障/兜底都在应用内闭环，无需外部 hdc |

## 许可证

- 本项目代码：**MIT**（见 LICENSE）
- DeepSeek-Reasonix：MIT（二进制随上游许可分发，声明见 THIRD_PARTY_LICENSES.md）
- Termony：MIT（fork 改造，原声明保留）
- qemu-vroot：GPL-2.0（经进程边界交互，不合并衍生；分发 HAP 时保持其源码可得）
- **结论：整体可自由商用/修改/分发，条件仅为保留版权与许可声明。**

## 路线图

- [ ] 鸿蒙设备实机联调（Termony + rootfs + bridge + Web UI 全链路）
- [x] resonix ACP 入口校准（`reasonix acp`，已按上游 docs/ACP.zh-CN.md 与 internal/cli 确认）
- [x] bridge ↔ ACP 引擎端到端协议验证（mock 引擎：三步 RPC + 推送通知全通）
- [ ] rootfs 首启自动引导（rawfile 释放 / 应用内下载）
- [ ] 会话持久化映射到应用沙箱目录；工具审批（PermissionRequest）原生弹窗
- [ ] 随 Termony 上游解锁手机端（deviceTypes 追加 phone）
- [ ] site/（resonix 官方 Astro Web UI）构建产物替换内嵌最小 UI（可选增强）

## 已知限制

- Termony 当前 deviceTypes 为 **2in1**（鸿蒙电脑/平板形态）；消费级 NEXT 手机端待上游解锁；
- resonix 官方未发布 linux-ohos 二进制，采用上游源码交叉编译 + rootfs 运行路径；
- 引擎能力受 rootfs 内工具链限制（git/bash 在 rootfs 内需 apk add）。
