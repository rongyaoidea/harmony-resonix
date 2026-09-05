# Third-Party Licenses / 第三方组件许可

本仓库（harmony-resonix）的原创代码以 MIT 发布（见 LICENSE）。
项目构建/运行依赖以下第三方成果，全部随分发的副本中保留其许可与版权声明。

## 1. DeepSeek-Reasonix

- 上游：https://github.com/esengine/DeepSeek-Reasonix （main-v2 分支）
- 许可：MIT License
- 版权：Copyright (c) 2026 Reasonix Contributors
- 使用方式：引擎以**未修改的二进制**（`GOOS=linux GOARCH=arm64 CGO_ENABLED=0`
  从上游源码交叉编译，或上游未来发布的官方二进制）运行于 Termony/qemu-vroot
  的 Alpine rootfs 内。本仓库不分发其源码修改；如产生补丁，按上游 MIT 与
  上游社区流程回馈。
- 完整许可文本（上游 LICENSE 原文）随每次发布附于 `licenses/DeepSeek-Reasonix-LICENSE`。

> 摘录（MIT 核心条款）：Permission is hereby granted, free of charge, to any
> person obtaining a copy of this software … to use, copy, modify, merge,
> publish, distribute, sublicense, and/or sell copies … subject to the
> following conditions: The above copyright notice and this permission notice
> shall be included in all copies or substantial portions of the Software.

## 2. Termony

- 上游：https://github.com/FunBocchi/Termony （master 分支，MIT）
- 版权：Copyright (c) Termony authors（以仓库 LICENSE 原文为准）
- 使用方式：本仓库 **fork / 二次开发** Termony 工程：
  - 新增 `entry/src/main/cpp/engine.{h,cpp}`（引擎进程管理）
  - `napi_init.cpp` 注册三个新 NAPI 方法
  - `entry/src/main/ets/pages/Index.ets` 重构为双 Tab 前端
  - `build-hnp/resonix` 新增 HNP 包
  以上修改以本仓库 MIT 发布；Termony 原有代码保持其原许可与声明。

## 3. 其他运行期组件

| 组件 | 许可 | 说明 |
|---|---|---|
| Alpine Linux rootfs | 各包原许可（musl MIT 等） | 用户自行下载部署，本仓库不分发 |
| qemu-vroot（Termony 内置） | GPL-2.0（qemu） | 由 Termony 以 HNP 分发，用户从上游获取 |
| Go 标准库 | BSD-3 | 编译 bridge 用 |

> 注意：qemu 为 GPL-2.0。**分发含 qemu-vroot 的 HAP 时需遵守 GPL 对该组件的
> 条款（提供其源码获取方式）**——Termony 上游已开源相关构建脚本，保持即可。
> bridge/resonix（MIT）与 qemu（GPL）通过进程边界交互（exec/spawn），不构成
> 衍生作品合并。

## 4. 分发清单（每次发布随附）

- [x] LICENSE（本项目 MIT）
- [x] THIRD_PARTY_LICENSES.md（本文件）
- [ ] licenses/DeepSeek-Reasonix-LICENSE（上游原文，构建 release 时复制）
- [ ] licenses/Termony-LICENSE（上游原文，构建 release 时复制）
- [ ] licenses/alpine-*（仅当分发 rootfs 时附各包清单；默认不分发）
