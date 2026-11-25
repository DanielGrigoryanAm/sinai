package realtime

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

// Hub keeps the sockets connected to this server, by user.
type Hub struct {
	mu    sync.RWMutex
	conns map[string]map[*conn]struct{}

	// Called with what a client sends, e.g. typing marks.
	OnClientEvent func(ctx context.Context, userID string, e ClientEvent)
	// Called when a user's first socket opens or last one closes.
	OnPresence func(userID string, online bool)
}

// ClientEvent is something a client sends over its socket.
type ClientEvent struct {
	Type string `json:"type"`
	Chat string `json:"chat"`
}

func NewHub() *Hub {
	return &Hub{conns: map[string]map[*conn]struct{}{}}
}

type conn struct {
	ws   *websocket.Conn
	send chan []byte
}

// Users lists who has a socket open on this server.
func (h *Hub) Users() []string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	ids := make([]string, 0, len(h.conns))
	for id := range h.conns {
		ids = append(ids, id)
	}
	return ids
}

// Online reports whether the user has a socket open on this server.
func (h *Hub) Online(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns[userID]) > 0
}

func (h *Hub) deliver(userIDs []string, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, id := range userIDs {
		for c := range h.conns[id] {
			select {
			case c.send <- payload:
			default:
				// Too slow to keep up: drop it rather than block everyone.
				// The client reloads what it missed when it reconnects.
				c.ws.Close(websocket.StatusPolicyViolation, "too slow")
			}
		}
	}
}

func (h *Hub) add(userID string, c *conn) (first bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[userID] == nil {
		h.conns[userID] = map[*conn]struct{}{}
	}
	h.conns[userID][c] = struct{}{}
	return len(h.conns[userID]) == 1
}

func (h *Hub) remove(userID string, c *conn) (last bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.conns[userID], c)
	if len(h.conns[userID]) == 0 {
		delete(h.conns, userID)
		return true
	}
	return false
}

// Serve upgrades a signed-in request to a socket and keeps it until it
// closes. userID is who the request belongs to.
func (h *Hub) Serve(w http.ResponseWriter, r *http.Request, userID string) {
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Apps, not browsers, connect; origin checks don't apply.
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}
	ws.SetReadLimit(4 << 10)
	c := &conn{ws: ws, send: make(chan []byte, 64)}
	if h.add(userID, c) && h.OnPresence != nil {
		h.OnPresence(userID, true)
	}
	defer func() {
		if h.remove(userID, c) && h.OnPresence != nil {
			h.OnPresence(userID, false)
		}
	}()

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	go h.write(ctx, c)

	for {
		_, data, err := ws.Read(ctx)
		if err != nil {
			return
		}
		var e ClientEvent
		if json.Unmarshal(data, &e) != nil {
			continue
		}
		if h.OnClientEvent != nil {
			h.OnClientEvent(ctx, userID, e)
		}
	}
}

// write sends queued events and pings now and then, so dead connections
// are noticed.
func (h *Hub) write(ctx context.Context, c *conn) {
	ping := time.NewTicker(25 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case payload := <-c.send:
			wctx, cancel := context.WithTimeout(ctx, 10*time.Second)
			err := c.ws.Write(wctx, websocket.MessageText, payload)
			cancel()
			if err != nil {
				return
			}
		case <-ping.C:
			pctx, cancel := context.WithTimeout(ctx, 10*time.Second)
			err := c.ws.Ping(pctx)
			cancel()
			if err != nil {
				slog.Debug("ping failed", "err", err)
				c.ws.Close(websocket.StatusGoingAway, "no pong")
				return
			}
		}
	}
}
