// Package users stores the people using the app.
package users

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

type User struct {
	ID        string     `json:"id"`
	Name      string     `json:"name"`
	PhotoURL  *string    `json:"photoUrl"`
	CreatedAt time.Time  `json:"createdAt"`
	LastSeen  *time.Time `json:"lastSeen"`
}

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

const maxNameLength = 40

// CleanName trims a display name and checks its length.
func CleanName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if utf8.RuneCountInString(name) > maxNameLength {
		return "", httpapi.BadRequest("Name is too long")
	}
	return name, nil
}

func (s *Store) Create(ctx context.Context, name string) (User, error) {
	var u User
	err := s.db.QueryRow(ctx, `
		INSERT INTO users (name) VALUES ($1)
		RETURNING id, name, photo_url, created_at, last_seen`, name).
		Scan(&u.ID, &u.Name, &u.PhotoURL, &u.CreatedAt, &u.LastSeen)
	return u, err
}

func (s *Store) Get(ctx context.Context, id string) (User, error) {
	var u User
	err := s.db.QueryRow(ctx, `
		SELECT id, name, photo_url, created_at, last_seen
		FROM users WHERE id = $1`, id).
		Scan(&u.ID, &u.Name, &u.PhotoURL, &u.CreatedAt, &u.LastSeen)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, httpapi.NotFound("User not found")
	}
	return u, err
}

func (s *Store) Rename(ctx context.Context, id, name string) (User, error) {
	var u User
	err := s.db.QueryRow(ctx, `
		UPDATE users SET name = $2 WHERE id = $1
		RETURNING id, name, photo_url, created_at, last_seen`, id, name).
		Scan(&u.ID, &u.Name, &u.PhotoURL, &u.CreatedAt, &u.LastSeen)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, httpapi.NotFound("User not found")
	}
	return u, err
}
