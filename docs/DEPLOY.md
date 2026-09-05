# DEPLOY — resonix 引擎部署到 Termony（qemu-vroot / Alpine rootfs）

> 目标设备：HarmonyOS Computer（2in1，如 MateBook Pro）。
> 消费级 NEXT 手机未验证（Termony 目前 deviceTypes 为 2in1）。

## 0. 前置

1. 构建机（任意 x86_64 Linux/macOS）完成 `engine/build-resonix.sh`，产出 `bridge`（arm64 静态 ELF，约 4.4MB）；
2. Termony 已安装到鸿蒙设备（FunBocchi/Termony，MIT），且能打开终端 Tab 执行 `bash`；
3. 下载 Alpine minirootfs aarch64（alpinelinux.org/downloads）。

## 1. 部署 rootfs 与引擎

### 路径一：App 内首次引导（已实现：检测 + 指引卡片）

Agent Tab 启动时用 `fs.accessSync` 检测 `<filesDir>/alpine_rootfs`；未部署则显示
引导卡片（三步说明 + 「复制部署命令」按钮，命令与路径二一致），部署完点「重试」。
rawfile 内置 rootfs 全自动释放仍为后续可选增强（会增加 HAP 体积）。

### 路径二：终端手动（当前验证路径）

在 resonix-harmony 的 **Terminal Tab**（即 Termony 原终端）里执行：

```sh
# 0) PC 侧：把两个文件推到应用沙箱 files 目录（hdcd 开发者模式为 root，可写）
#    <bundle> 换成实际包名（hdc shell bm dump -a 可查）
hdc file send alpine-minirootfs-3.22.0-aarch64.tar.gz \
  /data/app/el2/100/base/<bundle>/haps/entry/files/alpine.tar.gz
hdc file send bridge \
  /data/app/el2/100/base/<bundle>/haps/entry/files/bridge

# 1) App 内（Terminal Tab）：rootfs 到位
mkdir -p /data/storage/el2/base/haps/entry/files/alpine_rootfs
cd /data/storage/el2/base/haps/entry/files
tar xzf alpine.tar.gz -C alpine_rootfs

# 2) bridge 二进制放进 rootfs
cp bridge alpine_rootfs/usr/local/bin/bridge
chmod +x alpine_rootfs/usr/local/bin/bridge

# 3) 手动验证（关键！）
qemu-vroot-aarch64 -E PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -E HOME=/root -L /data/storage/el2/base/haps/entry/files/alpine_rootfs \
  /usr/local/bin/bridge --addr 127.0.0.1:8080 &
curl http://127.0.0.1:8080/healthz     # qemu-vroot 无独立网络栈，宿主直连可达
```

`/healthz` 返回 `ok` 即链路通，切到 Agent Tab 应自动加载 Web UI。

## 2. ACP 命令（已校准）

**已按上游源码确认**（docs/ACP.zh-CN.md + internal/cli/acp.go）：resonix 以
**子命令 `reasonix acp`** 运行 ACP JSON-RPC 2.0 stdio 服务（v2 线协议兼容，
方法：initialize / session/new / session/prompt / session/cancel）。
bridge 默认值即 `/usr/local/bin/reasonix acp`，无需再校准。

- 换模型：`reasonix acp --model deepseek-pro`（改 --acp-cmd 即可）；
- 首次配置：rootfs 内先跑 `reasonix setup` 完成 provider 认证；
- 若未来 ACP 入口变化，改 bridge 的 `--acp-cmd`（或 $ACP_CMD 环境变量）。

### 2.1 端到端协议验证（已通过）

在 x86 构建机上用 mock ACP 引擎（模拟 reasonix acp 的 JSON-RPC 应答）完成全链路测试：

```
WS客户端 → bridge(/ws) → stdin(\n结尾行) → mock_acp(stdio JSON-RPC)
         ← WS帧          ← stdout           ← 应答/推送
```

- [x] `initialize` → 返回 agentInfo
- [x] `session/new` → 返回 sessionId
- [x] `session/prompt` → 先收 `session/update` 推送通知，再收 `stopReason=end_turn` 应答
- [x] `session/request_permission` → 客户端允许后引擎收到 `allow_once`，继续执行

### 2.2 工具审批行为

ACP `session/request_permission`（引擎执行工具前征询）在 Web UI 内以
`confirm()` 处理——鸿蒙 Web 组件会将其渲染为**原生对话框**（确定=允许首个
`allow*` 选项，取消=选择首个 `reject*` 选项；无匹配选项时回退 `cancelled`）。
审批动作会在会话日志中留痕（✅/⛔ 行）。

### 2.3 rootfs 首启引导

AgentTab 启动引擎前先检测 `alpine_rootfs` 目录是否存在（`fs.accessSync`）：
未部署时不再盲目拉起引擎，而是显示三步部署指引卡片（下载 minirootfs →
`hdc file send` → 终端 Tab 解压），详见下文第 1 节。

**关键实现点**：ACP 为行分隔 JSON，bridge 向引擎 stdin 写入时必须保证消息以
`\n` 结尾，否则引擎按行读取会永久阻塞（此 bug 已在 main.go 修复并回归测试）。
真机验证时若 Web UI 卡在"连接引擎"，先在 Terminal Tab 手动跑
`/usr/local/bin/bridge --addr 127.0.0.1:8080` 观察日志。

## 3. 打包 HNP（可选：宿主直跑路径）

```sh
# Termony 仓库 build-hnp/ 下
mkdir -p resonix && cp -r <harmony-resonix>/hnp/resonix/* resonix/
cp <harmony-resonix>/engine/bridge/bin/bridge resonix/prebuilt/bridge
echo "	resonix \\" >> Makefile   # PKGS 列表追加（注意 Makefile 续行）
make resonix && make base.hnp && make copy
```

随后 DevEco Studio 打开 Termony 工程签名打包 hap。

> 注：rootfs 模式下 bridge 在 qemu-vroot 里跑，HNP 的 sysroot/bin/bridge
> 副本只是"宿主直跑"实验路径（OHOS musl 对纯静态 Go 二进制的兼容性待验证）。

## 4. 已知限制

| 项 | 状态 |
|---|---|
| Termony deviceTypes | 仅 2in1；手机端待 Termony 支持后自动解锁 |
| 内置 Terminal App | 无 mprotect R+X 权限，不能用 elf-loader，必须用 Termony |
| ELF 签名 | qemu-vroot 用户态模拟路径无需宿主签名；宿主直跑需 ohos-bst-light 自签 |
| Go 版本 | go.mod 若要求 >1.21，构建机需装新版 Go（golang.google.cn/dl） |
| WebView 明文 http | ArkWeb 默认放行 localhost http；若受限加 cleartextTraffic 配置 |
