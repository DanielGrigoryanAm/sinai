package push

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Service sends notifications to every device of a set of users, and
// forgets devices that are gone.
type Service struct {
	db     *pgxpool.Pool
	sender Sender // nil: pushes are off
}

func NewService(db *pgxpool.Pool, sender Sender) *Service {
	return &Service{db: db, sender: sender}
}

// Enabled reports whether pushes go anywhere.
func (s *Service) Enabled() bool { return s.sender != nil }

// SaveDevice remembers a device of userID. A token moves to the user who
// registered it last, so a shared phone notifies only who is signed in.
func (s *Service) SaveDevice(ctx context.Context, userID, token, platform string) error {
	_, err := s.db.Exec(ctx, `
		INSERT INTO device_tokens (token, user_id, platform) VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE
		SET user_id = excluded.user_id, platform = excluded.platform, updated_at = now()`,
		token, userID, platform)
	return err
}

// ForgetDevice drops a device, e.g. on sign-out.
func (s *Service) ForgetDevice(ctx context.Context, userID, token string) error {
	_, err := s.db.Exec(ctx,
		`DELETE FROM device_tokens WHERE token = $1 AND user_id = $2`, token, userID)
	return err
}

// ToUsers sends n to every device of userIDs in the background, so the
// request that caused it doesn't wait.
func (s *Service) ToUsers(userIDs []string, n Notification) {
	if s.sender == nil || len(userIDs) == 0 {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := s.send(ctx, userIDs, n); err != nil {
			slog.Error("push failed", "tag", n.Tag, "err", err)
		}
	}()
}

func (s *Service) send(ctx context.Context, userIDs []string, n Notification) error {
	rows, err := s.db.Query(ctx,
		`SELECT token FROM device_tokens WHERE user_id = ANY($1::uuid[])`, userIDs)
	if err != nil {
		return err
	}
	tokens, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return err
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	var dead []string
	sem := make(chan struct{}, 16) // at most 16 requests at once
	for _, token := range tokens {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer func() { <-sem; wg.Done() }()
			err := s.sender.Send(ctx, token, n)
			switch {
			case errors.Is(err, ErrDeadToken):
				mu.Lock()
				dead = append(dead, token)
				mu.Unlock()
			case err != nil:
				slog.Warn("push not delivered", "tag", n.Tag, "err", err)
			}
		}()
	}
	wg.Wait()

	if len(dead) > 0 {
		_, err = s.db.Exec(ctx, `DELETE FROM device_tokens WHERE token = ANY($1)`, dead)
	}
	slog.Info("pushes sent", "tag", n.Tag, "devices", len(tokens), "dead", len(dead))
	return err
}
