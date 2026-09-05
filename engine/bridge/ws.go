// ws.go — 最小 WebSocket 服务端实现（RFC 6455 服务端子集，零外部依赖）
//
// 仅支持本桥所需：握手、TEXT/BINARY 帧（客户端→服务端必为 masked）、
// 服务端→客户端 unmasked、Close/Ping/Pong 处理。生产增强（压缩、分片消息
// 重组）按需添加。选自实现是为了在离线构建机上 go build 一次通过。
package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
)

const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

type wsConn struct {
	conn net.Conn
	rw   *bufio.ReadWriter
	wmu  sync.Mutex // 帧写入互斥（stdout 泵与控制帧并发）
}

// upgrade：校验并完成 HTTP → WebSocket 握手
func wsUpgrade(w http.ResponseWriter, r *http.Request) (*wsConn, error) {
	if !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") ||
		!strings.Contains(strings.ToLower(r.Header.Get("Connection")), "upgrade") {
		http.Error(w, "expected websocket upgrade", http.StatusBadRequest)
		return nil, errors.New("not websocket")
	}
	key := r.Header.Get("Sec-WebSocket-Key")
	if key == "" {
		http.Error(w, "missing Sec-WebSocket-Key", http.StatusBadRequest)
		return nil, errors.New("missing key")
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijack unsupported", http.StatusInternalServerError)
		return nil, errors.New("hijack unsupported")
	}
	conn, rw, err := hj.Hijack()
	if err != nil {
		return nil, err
	}
	accept := sha1.New()
	accept.Write([]byte(key + wsGUID))
	acceptB64 := base64.StdEncoding.EncodeToString(accept.Sum(nil))

	var sb strings.Builder
	sb.WriteString("HTTP/1.1 101 Switching Protocols\r\n")
	sb.WriteString("Upgrade: websocket\r\n")
	sb.WriteString("Connection: Upgrade\r\n")
	sb.WriteString("Sec-WebSocket-Accept: " + acceptB64 + "\r\n\r\n")
	if _, err := rw.WriteString(sb.String()); err != nil {
		conn.Close()
		return nil, err
	}
	_ = rw.Flush()
	return &wsConn{conn: conn, rw: rw}, nil
}

// readFrame：读一帧（返回 fin 标志 + opcode + payload；客户端帧自动 unmask）
func (c *wsConn) readFrame() (fin bool, opcode byte, payload []byte, err error) {
	hdr := make([]byte, 2)
	if _, err = io.ReadFull(c.rw, hdr); err != nil {
		return
	}
	fin = hdr[0]&0x80 != 0
	opcode = hdr[0] & 0x0f
	masked := hdr[1]&0x80 != 0
	length := uint64(hdr[1] & 0x7f)
	switch length {
	case 126:
		ext := make([]byte, 2)
		if _, err = io.ReadFull(c.rw, ext); err != nil {
			return
		}
		length = uint64(binary.BigEndian.Uint16(ext))
	case 127:
		ext := make([]byte, 8)
		if _, err = io.ReadFull(c.rw, ext); err != nil {
			return
		}
		length = binary.BigEndian.Uint64(ext)
	}
	var mask [4]byte
	if masked {
		if _, err = io.ReadFull(c.rw, mask[:]); err != nil {
			return
		}
	}
	payload = make([]byte, length)
	if length > 0 {
		if _, err = io.ReadFull(c.rw, payload); err != nil {
			return
		}
	}
	if masked {
		for i := range payload {
			payload[i] ^= mask[i%4]
		}
	}
	return
}

// readMessage：读完整消息（处理分片），自动响应 Ping，Close 返回 EOF
func (c *wsConn) readMessage() (opcode byte, data []byte, err error) {
	var msg []byte
	for {
		fin, op, payload, err := c.readFrame()
		if err != nil {
			return 0, nil, err
		}
		switch op {
		case 0x8: // Close
			_ = c.writeFrame(0x8, payload)
			return 0, nil, io.EOF
		case 0x9: // Ping → Pong
			_ = c.writeFrame(0xA, payload)
			continue
		case 0xA: // Pong（客户端响应我们的 Ping；忽略）
			continue
		case 0x0, 0x1, 0x2: // Continuation / Text / Binary
			msg = append(msg, payload...)
			if fin {
				if op == 0x0 && len(msg) > 0 {
					// 分片序列结束：按文本处理
					return 0x1, msg, nil
				}
				return op, msg, nil
			}
		default:
			// 忽略未知帧
		}
	}
}

// writeFrame：写一帧（服务端 → 客户端，不 mask）
func (c *wsConn) writeFrame(opcode byte, payload []byte) error {
	c.wmu.Lock()
	defer c.wmu.Unlock()
	hdr := []byte{0x80 | opcode} // FIN=1
	n := len(payload)
	switch {
	case n < 126:
		hdr = append(hdr, byte(n))
	case n <= 0xFFFF:
		hdr = append(hdr, 126, byte(n>>8), byte(n))
	default:
		ext := make([]byte, 8)
		binary.BigEndian.PutUint64(ext, uint64(n))
		hdr = append(hdr, 127)
		hdr = append(hdr, ext...)
	}
	if _, err := c.rw.Write(hdr); err != nil {
		return err
	}
	if _, err := c.rw.Write(payload); err != nil {
		return err
	}
	return c.rw.Flush()
}

func (c *wsConn) writeMessage(opcode byte, data []byte) error { return c.writeFrame(opcode, data) }

func (c *wsConn) close() error { return c.conn.Close() }
