#!/usr/bin/env python3
# mock reasonix acp —— 模拟 internal/acp 的 JSON-RPC stdio 服务（v2 线协议）
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: m = json.loads(line)
    except: continue
    mid, method = m.get("id"), m.get("method")
    if method == "initialize":
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"protocolVersion":1,"agentInfo":{"name":"mock-reasonix","version":"0.0.1"}}}), flush=True)
    elif method == "session/new":
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"sessionId":"mock-s1"}}), flush=True)
    elif method == "session/prompt":
        text = "".join(c.get("text","") for c in m["params"].get("prompt",[]))
        upd = {"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"mock-s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":f"[mock] 收到: {text} → 已在鸿蒙 rootfs 内规划 3 步任务。"}}}}
        print(json.dumps(upd), flush=True)
        print(json.dumps({"jsonrpc":"2.0","id":mid,"result":{"stopReason":"end_turn"}}), flush=True)
