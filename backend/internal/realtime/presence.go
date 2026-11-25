package realtime

import (
	"context"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

// Presence tracks who is online across all servers. Each server stamps
// the users connected to it into a Redis sorted set every refresh; a user
// counts as online while their stamp is fresher than ttl. A server that
// dies just stops stamping, and its users go offline on their own.
type Presence struct {
	redis *redis.Client
	hub   *Hub
}

const (
	presenceKey     = "sinai:online"
	presenceRefresh = 20 * time.Second
	presenceTTL     = 60 * time.Second
)

func NewPresence(client *redis.Client, hub *Hub) *Presence {
	return &Presence{redis: client, hub: hub}
}

// Online reports which of ids are online.
func (p *Presence) Online(ctx context.Context, ids []string) map[string]bool {
	online := make(map[string]bool, len(ids))
	if len(ids) == 0 {
		return online
	}
	scores, err := p.redis.ZMScore(ctx, presenceKey, ids...).Result()
	if err != nil {
		return online
	}
	fresh := float64(time.Now().Add(-presenceTTL).Unix())
	for i, id := range ids {
		online[id] = scores[i] > fresh
	}
	return online
}

// Set marks a user online now, or offline at once.
func (p *Presence) Set(ctx context.Context, userID string, online bool) {
	at := time.Now()
	if !online {
		at = at.Add(-presenceTTL - time.Second)
	}
	p.redis.ZAdd(ctx, presenceKey, redis.Z{Score: float64(at.Unix()), Member: userID})
}

// Run keeps this server's users stamped until ctx ends, and drops stamps
// long gone so the set doesn't grow forever.
func (p *Presence) Run(ctx context.Context) {
	tick := time.NewTicker(presenceRefresh)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		now := float64(time.Now().Unix())
		users := p.hub.Users()
		if len(users) > 0 {
			zs := make([]redis.Z, len(users))
			for i, id := range users {
				zs[i] = redis.Z{Score: now, Member: id}
			}
			p.redis.ZAdd(ctx, presenceKey, zs...)
		}
		old := strconv.FormatInt(time.Now().Add(-24*time.Hour).Unix(), 10)
		p.redis.ZRemRangeByScore(ctx, presenceKey, "-inf", old)
	}
}
