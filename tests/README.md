# tests/ — 端到端协议验证

在任意 x86_64 Linux 构建机上复现 bridge ↔ ACP 引擎全链路验证（无需鸿蒙设备）。

## 组成

| 文件 | 作用 |
|---|---|
| `mock_acp.py` | 模拟 `reasonix acp` 的 JSON-RPC stdio 引擎（initialize / session/new / session/prompt 应答 + session/update 推送） |
| `test_e2e.py` | 起一个真 bridge 进程 + 最小 WebSocket 客户端，走完三步 RPC 并断言应答 |

## 运行

```sh
# 1. 编译 x86 版 bridge（或直接用已有二进制）
cd engine/bridge && CGO_ENABLED=0 go build -o /tmp/bridge-x86 . && cd ../..

# 2. 跑端到端测试（参数为监听端口）
python3 tests/test_e2e.py 18082
```

预期输出：

```
  initialize -> {'name': 'mock-reasonix', 'version': '0.0.1'}
  session/new -> mock-s1
  [push] {"jsonrpc": "2.0", "method": "session/update", ...
  session/prompt -> stopReason=end_turn
E2E PASS ✅
```

## 覆盖点

- WS 握手（RFC6455）、客户端帧掩码、文本帧收发
- WS → 引擎 stdin（**行分隔 JSON：bridge 补 `\n`** 的回归保护）
- 引擎 stdout → WS（含 push 通知与 RPC 应答乱序到达）
- 引擎生命周期（连接断开 → 引擎终止）
