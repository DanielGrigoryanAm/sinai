// Package auth signs users in and keeps their sessions.
//
// A session is a pair of tokens: a short-lived JWT access token sent with
// every request, and a long-lived random refresh token that buys a new
// pair. Refresh tokens are single use; presenting one that was already
// used ends every session of that user, as it means it was stolen.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrInvalidToken = errors.New("invalid token")

type Tokens struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
	// Seconds until the access token expires.
	ExpiresIn int `json:"expiresIn"`
}

type Service struct {
	db         *pgxpool.Pool
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewService(db *pgxpool.Pool, secret []byte, accessTTL, refreshTTL time.Duration) *Service {
	return &Service{db: db, secret: secret, accessTTL: accessTTL, refreshTTL: refreshTTL}
}

// Issue starts a new session for userID.
func (s *Service) Issue(ctx context.Context, userID string) (Tokens, error) {
	return s.issue(ctx, s.db, userID)
}

// querier is a pool or a transaction.
type querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

func (s *Service) issue(ctx context.Context, q querier, userID string) (Tokens, error) {
	now := time.Now()
	access, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Subject:   userID,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(s.accessTTL)),
	}).SignedString(s.secret)
	if err != nil {
		return Tokens{}, err
	}

	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return Tokens{}, err
	}
	refresh := base64.RawURLEncoding.EncodeToString(raw)
	if _, err := q.Exec(ctx, `
		INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)`,
		userID, hash(refresh), now.Add(s.refreshTTL)); err != nil {
		return Tokens{}, fmt.Errorf("store refresh token: %w", err)
	}

	return Tokens{
		AccessToken:  access,
		RefreshToken: refresh,
		ExpiresIn:    int(s.accessTTL.Seconds()),
	}, nil
}

// Refresh trades a refresh token for a new pair of tokens.
func (s *Service) Refresh(ctx context.Context, refresh string) (Tokens, error) {
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return Tokens{}, err
	}
	defer tx.Rollback(ctx)

	var id, userID string
	var expiresAt time.Time
	var revokedAt *time.Time
	err = tx.QueryRow(ctx, `
		SELECT id, user_id, expires_at, revoked_at
		FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
		hash(refresh)).Scan(&id, &userID, &expiresAt, &revokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Tokens{}, ErrInvalidToken
	}
	if err != nil {
		return Tokens{}, err
	}

	if revokedAt != nil {
		// Used twice: someone else has it. End all of the user's sessions.
		// Done in this transaction, which already holds the row's lock.
		if _, err := tx.Exec(ctx, `
			UPDATE refresh_tokens SET revoked_at = now()
			WHERE user_id = $1 AND revoked_at IS NULL`, userID); err != nil {
			return Tokens{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return Tokens{}, err
		}
		return Tokens{}, ErrInvalidToken
	}
	if time.Now().After(expiresAt) {
		return Tokens{}, ErrInvalidToken
	}

	if _, err := tx.Exec(ctx,
		`UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1`, id); err != nil {
		return Tokens{}, err
	}
	tokens, err := s.issue(ctx, tx, userID)
	if err != nil {
		return Tokens{}, err
	}
	return tokens, tx.Commit(ctx)
}

// Revoke ends the session of a refresh token. Unknown tokens are ignored.
func (s *Service) Revoke(ctx context.Context, refresh string) error {
	_, err := s.db.Exec(ctx, `
		UPDATE refresh_tokens SET revoked_at = now()
		WHERE token_hash = $1 AND revoked_at IS NULL`, hash(refresh))
	return err
}

// Verify checks an access token and returns the user it belongs to.
func (s *Service) Verify(access string) (string, error) {
	claims := &jwt.RegisteredClaims{}
	_, err := jwt.ParseWithClaims(access, claims, func(*jwt.Token) (any, error) {
		return s.secret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil || claims.Subject == "" {
		return "", ErrInvalidToken
	}
	return claims.Subject, nil
}

func hash(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}
