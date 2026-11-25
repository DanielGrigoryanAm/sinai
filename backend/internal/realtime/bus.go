// Package realtime delivers live events (new messages, reactions, typing,
// game moves) to connected clients over WebSockets.
//
// Every server instance publishes events to Redis and listens for all of
// them, then hands each event to the sockets of its recipients that are
// connected to that instance. So two people in a chat can sit on
// different servers.
package realtime

import (
	"context"
	"encoding/json"
	"log/slog"

	"github.com/redis/go-redis/v9"
)

const channel = "sinai:events"

// Event is one thing that happened, for the users in To.
type Event struct {
	Type string          `json:"type"`
	Chat string          `json:"chat,omitempty"`
	Data any             `json:"data,omitempty"`
	To   []string        `json:"to"`
}

// Bus sends events through Redis to the hub of every server.
type Bus struct {
	redis *redis.Client
	hub   *Hub
}

func NewBus(client *redis.Client, hub *Hub) *Bus {
	return &Bus{redis: client, hub: hub}
}

// Publish sends an event. Failures are logged, not returned: the change
// itself is already saved and clients catch up when they reload.
func (b *Bus) Publish(ctx context.Context, e Event) {
	if len(e.To) == 0 {
		return
	}
	payload, err := json.Marshal(e)
	if err != nil {
		slog.Error("encode event", "type", e.Type, "err", err)
		return
	}
	if err := b.redis.Publish(ctx, channel, payload).Err(); err != nil {
		slog.Error("publish event", "type", e.Type, "err", err)
	}
}

// Run hands events from Redis to this server's hub until ctx ends.
func (b *Bus) Run(ctx context.Context) {
	sub := b.redis.Subscribe(ctx, channel)
	defer sub.Close()
	for msg := range sub.Channel() {
		var e struct {
			Type string          `json:"type"`
			Chat string          `json:"chat,omitempty"`
			Data json.RawMessage `json:"data,omitempty"`
			To   []string        `json:"to"`
		}
		if err := json.Unmarshal([]byte(msg.Payload), &e); err != nil {
			slog.Warn("bad event", "err", err)
			continue
		}
		out, _ := json.Marshal(struct {
			Type string          `json:"type"`
			Chat string          `json:"chat,omitempty"`
			Data json.RawMessage `json:"data,omitempty"`
		}{e.Type, e.Chat, e.Data})
		b.hub.deliver(e.To, out)
	}
}
