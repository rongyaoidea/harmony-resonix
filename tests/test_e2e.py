#!/usr/bin/env python3
# 端到端测试：bridge(WS) ↔ mock_acp(stdio JSON-RPC) 全链路
import socket, base64, os, json, time, sys, subprocess, urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18082

def ws_connect(port):
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (f"GET /ws HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    s.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(4096)
    assert b"101" in resp.split(b"\r\n")[0], resp
    return s

def ws_send(s, obj):
    payload = json.dumps(obj).encode()
    mask = os.urandom(4)
    hdr = bytearray([0x81])
    n = len(payload)
    if n < 126: hdr.append(0x80 | n)
    elif n < 65536: hdr.append(0x80 | 126); hdr += n.to_bytes(2, "big")
    else: hdr.append(0x80 | 127); hdr += n.to_bytes(8, "big")
    hdr += mask
    s.sendall(bytes(hdr) + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

def ws_recv(s, timeout=5):
    s.settimeout(timeout)
    def rd(n):
        d = b""
        while len(d) < n:
            c = s.recv(n - len(d))
            if not c: raise ConnectionError("peer closed")
            d += c
        return d
    hdr = rd(2)
    op = hdr[0] & 0x0F
    n = hdr[1] & 0x7F
    if n == 126: n = int.from_bytes(rd(2), "big")
    elif n == 127: n = int.from_bytes(rd(8), "big")
    data = rd(n)
    if op == 0x9:  # ping → 交由上层处理
        return ("ping", data)
    return (op, json.loads(data))

def rpc(s, m, expect_id, timeout=5):
    ws_send(s, m)
    deadline = time.time() + timeout
    while time.time() < deadline:
        op, msg = ws_recv(s, timeout=deadline - time.time())
        if op == "ping":
            continue
        # 引擎的工具审批请求：自动允许（覆盖 request_permission 往返）
        if msg.get("method") == "session/request_permission":
            opts = msg["params"].get("options", [])
            allow = next((o for o in opts if str(o.get("kind","")).startswith("allow")), opts[0])
            ws_send(s, {"jsonrpc":"2.0","id":msg["id"],
                        "result":{"outcome":{"outcome":"selected","optionId":allow["optionId"]}}})
            print(f"  [perm] auto-allowed: {msg['params'].get('toolCall',{}).get('title','')}")
            continue
        if msg.get("id") == expect_id:
            return msg
        print(f"  [push] {json.dumps(msg, ensure_ascii=False)[:110]}")
    raise TimeoutError(f"no reply for id={expect_id}")

# ---- 启动 bridge ----
env = dict(os.environ, ACP_CMD="python3 /tmp/mock_acp.py")
proc = subprocess.Popen(["/tmp/bridge-x86", "--addr", f"127.0.0.1:{PORT}"], env=env,
                        stdout=open("/tmp/bridge-e2e.log", "w"), stderr=subprocess.STDOUT)
for _ in range(30):
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{PORT}/healthz", timeout=1)
        break
    except Exception:
        time.sleep(0.2)

try:
    s = ws_connect(PORT)
    r1 = rpc(s, {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientInfo":{"name":"e2e-test"}}}, 1)
    assert r1["result"]["agentInfo"]["name"] == "mock-reasonix", r1
    print(f"  initialize -> {r1['result']['agentInfo']}")

    r2 = rpc(s, {"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/root","mcpServers":[]}}, 2)
    assert r2["result"]["sessionId"] == "mock-s1", r2
    print(f"  session/new -> {r2['result']['sessionId']}")

    r3 = rpc(s, {"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"mock-s1","prompt":[{"type":"text","text":"在鸿蒙rootfs里列出当前目录"}]}}, 3)
    updates = []
    # prompt 的 push 通知在 rpc 循环里已打印；这里 r3 是 stopReason 应答
    assert r3["result"]["stopReason"] == "end_turn", r3
    print(f"  session/prompt -> stopReason=end_turn, push 通知见上")
    s.close()
    print("E2E PASS ✅  (initialize / session/new / session/prompt 全链路通)")
finally:
    proc.terminate()
    time.sleep(0.3)
    with open("/tmp/bridge-e2e.log") as f:
        print("---- bridge log ----")
        print(f.read().strip())
