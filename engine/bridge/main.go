// bridge — resonix Web 桥（鸿蒙侧运行）
//
// 职责（零外部依赖，纯 Go，离线可编译）：
//   1. spawn resonix 引擎进程（ACP 模式，JSON-RPC 2.0 over stdio）
//   2. WebSocket /ws ↔ 引擎 stdin/stdout 双向透传
//   3. GET /            → 内嵌极简 Web UI（聊天式 ACP 客户端）
//   4. GET /healthz     → 探活（ArkTS AgentTab 用它判断引擎就绪）
//
// 构建（任意 x86 构建机）：
//   CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o bin/bridge .
//
// 运行（Termony qemu-vroot / Alpine rootfs 内）：
//   /usr/local/bin/bridge --addr 127.0.0.1:8080
//
// 环境变量 / 参数：
//   --acp-cmd  引擎 ACP 启动命令（默认取 $ACP_CMD，再默认
//              "/usr/local/bin/reasonix acp" —— 已按上游 docs/ACP.zh-CN.md 确认：
//              resonix 以子命令 `reasonix acp` 运行 ACP JSON-RPC 2.0 stdio 服务，
//              v2 线协议：initialize / session/new / session/prompt / session/cancel）
package main

import (
	"embed"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"sync"
)

//go:embed index.html
var webUI embed.FS

var acpCmd = flag.String("acp-cmd", envOr("ACP_CMD", "/usr/local/bin/reasonix acp"), "引擎 ACP 启动命令")
var addr = flag.String("addr", "127.0.0.1:8080", "监听地址")

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

// session：一个 WS 连接对应一个引擎子进程，stdin/stdout 与 WS 互泵
type session struct {
	mu    sync.Mutex
	cmd   *exec.Cmd
	stdin io.WriteCloser
	ws    *wsConn
}

func (s *session) start() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cmd != nil {
		return nil
	}
	cmd := exec.Command("/bin/sh", "-c", *acpCmd)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	s.cmd, s.stdin = cmd, stdin
	log.Printf("engine spawned: %s", *acpCmd)

	// 引擎 stdout → WS（引擎 → 浏览器）
	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := stdout.Read(buf)
			if n > 0 {
				if werr := s.ws.writeMessage(0x1, buf[:n]); werr != nil {
					return
				}
			}
			if err != nil {
				log.Printf("engine stdout closed: %v", err)
				_ = s.ws.close()
				return
			}
		}
	}()

	// 进程退出时关 WS，让前端感知
	go func() {
		_ = cmd.Wait()
		log.Printf("engine exited")
		_ = s.ws.close()
	}()
	return nil
}

func handleWS(w http.ResponseWriter, r *http.Request) {
	ws, err := wsUpgrade(w, r)
	if err != nil {
		return
	}
	s := &session{ws: ws}
	if err := s.start(); err != nil {
		log.Printf("engine spawn failed: %v", err)
		msg := fmt.Sprintf(`{"jsonrpc":"2.0","id":0,"error":{"code":-32000,"message":"engine spawn failed: %s"}}`, err.Error())
		_ = ws.writeMessage(0x1, []byte(msg))
		_ = ws.close()
		return
	}
	defer func() {
		if s.cmd != nil && s.cmd.Process != nil {
			_ = s.cmd.Process.Kill()
		}
	}()

	// WS → 引擎 stdin（浏览器 → 引擎）
	for {
		_, data, err := ws.readMessage()
		if err != nil {
			return
		}
		// ACP 为行分隔 JSON 协议：确保每条消息以 \n 结尾，
		// 否则引擎按行读取时会一直阻塞、应答永远发不回来
		if len(data) == 0 || data[len(data)-1] != '\n' {
			data = append(data, '\n')
		}
		if _, err := s.stdin.Write(data); err != nil {
			log.Printf("engine stdin write: %v", err)
			return
		}
	}
}

func main() {
	flag.Parse()

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, "ok")
	})
	http.HandleFunc("/ws", handleWS)
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		b, _ := webUI.ReadFile("index.html")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(b)
	})

	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatalf("listen %s: %v", *addr, err)
	}
	log.Printf("bridge listening on http://%s  (ACP: %s)", *addr, *acpCmd)
	log.Fatal(http.Serve(ln, nil))
}
