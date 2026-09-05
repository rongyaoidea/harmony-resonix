# 鸿蒙前后端开发调研报告（RESEARCH）

> 调研时间：2026-09 · 调研目的：回答「HAP 构建状态 / 工具链来源」两问，并为前端 UI
> 优化（finesse-ui × Claude 主题）提供设计依据。本报告为 `docs/` 存档，结论已落地到代码。

---

## 1. 是否编译成鸿蒙手机可用直接安装的格式？

**结论：尚未产出可安装的 HAP；工程已具备全部构建前提。**

| 事项 | 状态 | 说明 |
|---|---|---|
| HAP（`*.hap` 安装包） | ❌ 未构建 | 需要 HarmonyOS Command Line Tools（`hvigorw assembleHap`）+ 签名证书 |
| bridge（Go arm64 静态） | ✅ 已构建 | `hnp/resonix/prebuilt/bridge`（5.9MB，`GOOS=android GOARCH=arm64`） |
| reasonix CLI（arm64 静态） | ✅ 已构建 | 43MB，rootfs 内运行 |
| 应用层 ArkTS/C++ 源码 | ✅ 就绪 | Termony 补丁工程 + NAPI 引擎模块 |
| 侧载方案 | ✅ 可行 | 无签名调试可用 `hdc install`（开发者模式）；正式分发需 AGC 签名 |

**HAP 命令行构建链（调研确认，Linux 主机可用）：**

- 华为官方 **Command Line Tools** 集合了 `codelinter / ohpm / hstack / hvigorw`，
  **SDK 已嵌入命令行工具包，无需额外下载**；Linux 主机无法安装 DevEco Studio
  （仅 Windows/macOS），但命令行工具支持 Linux（默认落盘 `~/Huawei/ohos-sdk/openharmony/<ver>/`）。
- 构建：`hvigorw clean → assembleHap`（调试包）/ `assembleApp`（发布包）。
- 依赖：JDK 11+、Node.js 20.18.1；ohpm 需换国内镜像 `https://ohpm.openharmony.cn/ohpm/`。
- 签名：`hap-sign-tool`（位于 SDK toolchains 内）；**路径不能含中文**。
- 后续动作（工程外）：在装有 DevEco Studio 的机器上或 Linux + Command Line Tools
  环境执行 `hvigorw assembleHap`，配合调试证书即可出包。

## 2. 是否用了第三方编译构建工具？

**结论：零第三方编译/构建工具，全部官方工具链。**

| 组件 | 工具 | 来源 |
|---|---|---|
| bridge / reasonix | Go 官方交叉编译器（`go build`，CGO 关闭，纯静态） | golang.org（经阿里云镜像下载） |
| Web UI | 无构建步骤 | 手写单文件 HTML/CSS/JS（内嵌于 bridge） |
| ArkTS / C++ 层 | （构建时）hvigor + LLVM，属鸿蒙 SDK 官方链 | 华为/开源 OpenHarmony SDK |
| 上游依赖 | Termony（MIT）、resonix（MIT）——仅源码引用 | GitHub |

`scripts/build-all.sh` 中唯一的「第三方」是 **go mod 模块代理**（`goproxy.cn`，仅加速
依赖下载，不参与编译）与 ghproxy（仅 git 克隆加速）。编译器本身均为官方原版。

## 3. finesse-ui 调研（前端设计 skill）

- **定位**：Claude Code / Codex / Cursor / CodeBuddy 生态的 UI 设计 skill
  （`npx skills add https://github.com/mouse-lin/finesse-skill`，官网 finesseui.com）。
- **双 register（设计路线）**：
  - **brand**：设计即产品——landing/官网场景；grain 噪点、vignette 暗角、五类 hero 视觉引擎；
  - **product**：仪表盘/admin/工具场景——**clarity（清晰）+ density（密度）优先**。
  - 本项目聊天 UI 属 product register。
- **核心原则（已落地）**：
  - **tinted neutrals**：禁纯 `#fff`/`#000` 大面积背景，中性色带色调倾向；
  - **translucent / hairline 边框**：1px 低饱和细线代替粗边框；
  - **tinted shadows**：阴影带色相（本项目用暖黑 `rgba(20,20,19,…)`）；
  - **反 AI-slop 黑名单**：无渐变横幅、无霓虹色、无默认蓝紫、无 emoji 装饰堆砌；
  - **OKLCH 配色阶梯**：统一色相下按明度阶梯取色。

## 4. Claude 主题设计规格（本次落地采用的 token）

来源：Anthropic 公开设计体系（anthropic.com / claude.ai 反向整理，多源交叉验证）。

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| canvas（parchment） | `#F5F4ED` | `#141413` | 页面画布（暖米色/暖近黑，非纯白黑） |
| surface（ivory） | `#FAF9F5` | `#1F1E1D` | 卡片、输入框 |
| sand | `#E8E6DC` | `#30302E` | 用户消息气泡 |
| ink（carbon ink） | `#141413` | `#FAF9F5` | 主文本 |
| ink-2/3/4 | `#373734`/`#7B7974`/`#9C9A92` | 降透明/灰阶 | 次要/弱化文本（全部暖调） |
| line（chalk/mist） | `#E7E6E1`/`#B7B7B5` | `#30302E`/`#4A4A47` | hairline 边框 |
| brand（terracotta） | `#C96442` | `#D97757`(clay) | 品牌 ✳、审批卡片强调、聚焦环 |
| error / ok | `#B53333` / `#629987` | 提亮 | 拒绝 / 完成 |
| code-bg | `#F0EEE6` | `#1B1A19` | 行内代码、代码块 |
| shadow | 暖黑 `rgba(20,20,19,.05~.07)` | `rgba(0,0,0,.3~.35)` | tinted shadow |

- **字体**：标题衬线（Georgia → Source Serif 4 → Charter，映射 Anthropic Serif 的气质）、
  正文 system-ui / HarmonyOS Sans、代码 ui-monospace。
- **几何**：气泡 16px 圆角、卡片 12-16px、按钮 pill（999px）、控件 8px。
- **标志性细节**：✳ asterisk 品牌标记（Claude 8 辐条星号）、思考中三圆点跳动、
  空状态衬线问候「今天想做点什么？」、建议 chips、聚焦 ring 用 brand 色。

## 5. ArkWeb 前端文档要点（发现并修复 1 个真 bug）

- **`onConfirm` 官方行为**：网页 `confirm()` 触发回调；**回调返回 `true` 表示应用自行绘制
  弹窗**，且**必须**调用 `JsResult.handleConfirm()` / `handleCancel()`（可异步），否则
  **渲染进程阻塞**；返回 `false` 视为取消。ArkWeb **不会自动弹出**任何 JS 对话框。
- **审查发现**：此前 `Index.ets` 在 `onConfirm` 中直接 `handleConfirm(true)`——等于所有
  审批**自动放行**且不给用户选择，属逻辑错误。已改为 `getUIContext().showAlertDialog()`
  真实弹窗（取消/确定 双键，`autoCancel:false`）。
- **配套改造**：Web UI 内的工具审批不再走 `confirm()`，改为**应用内自定义审批卡片**
  （忠实呈现 ACP `session/request_permission` 的 options：主按钮=allow 项、ghost=reject
  项、其余选项链接补列），双保险且体验更佳。
- `onAlert`/`onBeforeUnload` 同理：必须应答 `JsResult`，否则渲染进程阻塞。
- 移动端细节：`viewport-fit=cover` + `env(safe-area-inset-*)` 适配挖孔屏/手势条。

## 6. ArkUI / NAPI 后端要点（现状评估）

- **Tab 组件**：`Tabs({barPosition: BarPosition.End})` + `TabContent().tabBar()`
  ——底部双 Tab（Agent / Terminal）为官方推荐形态。
- **状态管理**：`@State` 驱动 `engineUrl/engineStatus/rootfsMissing/bootFailed` 四态渲染
  （状态页 ↔ Web 页分支）；异步探活循环内直接赋值刷新，符合声明式范式。
- **`showAlertDialog`**：`this.getUIContext().showAlertDialog({...})`，`primaryButton`/
  `secondaryButton` 的 `action` 内异步应答 `JsResult`（官方示例同款模式）。
- **NAPI（engine.cpp）**：`fork + setsid + execv` 拉起 qemu-vroot；已审查修复
  `argc<2` 返回 `-1`（此前 `undefined` 误判）、dup2 后关闭冗余 fd、进程退出状态重置。
  线程模型为「ArkTS 异步轮询 + C++ 一次性 spawn」，无锁竞争面。
- **网络通道**：qemu-vroot 用户态模拟无独立网络栈，rootfs 内监听端口宿主直接可达
  （`127.0.0.1:8080`），ArkWeb 直连本地 bridge，无需跨进程 IPC。

## 7. 调研 → 落地对照

| 调研结论 | 落地位置 |
|---|---|
| product register：clarity+density+tinted neutrals | `engine/bridge/index.html` 全量重写 |
| Claude token 表（§4） | 同上 `:root` CSS 变量 + 深色 media query |
| ArkWeb onConfirm 必须应答且不可自动放行 | `termony-patches/ets/pages/Index.ets` `showAlertDialog` |
| 审批 UI 产品化 | index.html 自定义审批卡片（ACP options 忠实呈现） |
| HAP 命令行构建链 | §1 存档（工程外环境执行） |
| 移动端安全区 | viewport-fit=cover + env(safe-area-inset-*) |

## 8. 鸿蒙运行 Linux 后端环境的方案矩阵（2026-09 补充调研）

> 结论先行：**qemu-user（当前路线）是免 root、跨手机/平板/2in1 的均衡解**；
> 追求完整网络栈选 **HiSH（qemu-system 全系统模拟）**；PC 上追求原生性能可试
> **proot（HNP 生态已适配）或 ohos-bst-light 自签直跑**；零风险兜底是 **SSH 远程**。

| 路线 | 代表项目/工具 | 原理 | 手机 | 完整内核/网络栈 | 关键限制 |
|---|---|---|---|---|---|
| **用户态指令翻译**（当前） | Termony（qemu-vroot，qemu-linux-user fork） | 有签名的 qemu-user 加载未签名 Linux ELF，逐指令翻译 + syscall 转发，共享宿主内核 | ✅ | ❌ 共享宿主网络栈（loopback 直达宿主，本项目正利用此点） | TCG 有性能损耗；宿主 seccomp 仍约束全部 syscall |
| **用户态 ptrace 虚拟化** | proot（termux/proot + ohos.patch，鸿蒙 PC HNP 生态已构建成功） | ptrace 拦截/重定向 syscall，实现无 root chroot/bind-mount/binfmt；同架构**零指令翻译** | ⚠️ PC 已验证，手机待验证（需 seccomp 放行 ptrace） | ❌ 同上（共享宿主内核） | 依赖 ptrace 可用性；被拦截 syscall 同样受限 |
| **全系统模拟** | **HiSH**（harmoninux/HiSH，基于 hackeris/harmony-qemu） | qemu-system-aarch64 TCG 跑**完整 arm64 Linux 内核** + qcow2 rootfs | ✅（应用市场版无 JIT；自签版有 JIT，Phone 不支持 JIT） | ✅ **独立内核 + 独立网络栈 + 端口转发 + 共享文件夹** | TCG 性能一般；rootfs 镜像体积大；「关于」页需注明基于 HiSH（其许可要求） |
| **ELF 自签直跑**（零模拟） | ohos-bst-light（self-sign.c）/ 官方 binary-sign-tool | 给 Linux ELF 附加 `.codesign` 段，直接跑在鸿蒙宿主 musl 上 | ❌ **仅鸿蒙 6 PC（HiShell）**，鸿蒙 5 不支持 | ❌（无隔离，直跑宿主） | 仅静态/自包含二进制（glibc 动态链接不行）；seccomp 拦截的 syscall（如 close_range）需 LD_PRELOAD 垫片；社区已用此法在鸿蒙 PC 跑通 Claude Code（Bun 版） |
| **硬件虚拟化（KVM 类）** | 无 | 三方应用拿不到 EL2/虚拟化 API | ❌ | — | 官方未开放，不可行 |
| **远程 Linux（兜底）** | SSH 客户端 / 华为云 DevBox | 手机做瘦客户端连云端/局域网 Linux | ✅ | ✅（在远端） | 依赖网络；无离线能力 |

### 对本工程的具体建议

1. **保持 qemu-vroot 为主线**：唯一同时满足「免 root + 手机/平板/PC 三端 + 无第三方 App 依赖」的路线；本项目 Web 桥架构（loopback 直达宿主）恰好规避了 qemu-user 无独立网络栈的短板。
2. **性能升级备选**：同架构下把 qemu-vroot 换成 **proot** 可省掉指令翻译（理论上显著提速），且 rootfs 布局不变（bridge/reasonix 二进制可复用）；风险点是手机端 ptrace 是否被 seccomp 放行——实机验证后可作 build 选项。
3. **重依赖发行版场景**：若未来需要 apt 全量生态（GPU/桌面/数据库），**HiSH** 是现成容器：把 bridge/reasonix 装进其 Ubuntu/Debian rootfs，App 侧 UI 改连 HiSH 的端口转发地址即可，工程架构无需改动。
4. **鸿蒙 6 PC 专属捷径**：bridge 为 Go **纯静态** ELF，是 ohos-bst-light 自签直跑的理想候选——若验证通过，2in1 上可**完全去掉 qemu/rootfs 层**（直跑宿主 musl），详见 docs/DEPLOY.md「宿主直跑」实验路径。
5. **零风险兜底**：bridge 本就监听 TCP，把 `--addr` 绑到局域网 + UI 的 engineUrl 指向远端，即是 SSH/远程部署形态，任何鸿蒙设备可用。

来源：HiSH（github.com/zzh-FLY/HiSH、harmoninux/HiSH）、harmony-qemu（hackeris）、
proot 鸿蒙 PC 构建指南（CSDN 开源鸿蒙PC社区 harmonypc.csdn.net）、ohos-bst-light
（github.com/hqzing/ohos-bst-light）与鸿蒙 PC 运行 Claude Code 实践（HarmonyOS 开发者社区）、
虎绿林 binary-sign-tool 讨论。
