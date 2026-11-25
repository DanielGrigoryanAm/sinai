// Package chats keeps chats and who is in them. A chat is joined by its
// six-character code, which is also its id.
package chats

import (
	"context"
	"crypto/rand"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

type Chat struct {
	Code      string    `json:"code"`
	OwnerID   string    `json:"ownerId"`
	Name      string    `json:"name"`
	PhotoURL  *string   `json:"photoUrl"`
	Game      any       `json:"game"`
	CreatedAt time.Time `json:"createdAt"`
	Members   []Member  `json:"members,omitempty"`
}

type Member struct {
	UserID   string     `json:"userId"`
	Name     string     `json:"name"`
	PhotoURL *string    `json:"photoUrl"`
	JoinedAt time.Time  `json:"joinedAt"`
	LastSeen *time.Time `json:"lastSeen"`
	Online   bool       `json:"online"`
	ReadAt   *time.Time `json:"readAt"`
}

// Summary is a chat as the chat list shows it.
type Summary struct {
	Chat
	LastMessage *LastMessage `json:"lastMessage"`
	Unread      int          `json:"unread"`
}

type LastMessage struct {
	ID         string    `json:"id"`
	SenderID   *string   `json:"senderId"`
	SenderName string    `json:"senderName"`
	Text       string    `json:"text"`
	Kind       string    `json:"kind"` // text, image or voice
	CreatedAt  time.Time `json:"createdAt"`
}

var (
	ErrNotMember = httpapi.NotFound("Chat not found")
	ErrNotOwner  = &httpapi.Error{Status: 403, Code: "forbidden", Message: "Only the owner can do this"}
)

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no 0/O, 1/I

func newCode() string {
	b := make([]byte, 6)
	rand.Read(b)
	for i := range b {
		b[i] = codeAlphabet[int(b[i])%len(codeAlphabet)]
	}
	return string(b)
}

// Create makes a chat owned by ownerID, who becomes its first member.
func (s *Store) Create(ctx context.Context, ownerID, name string) (Chat, error) {
	for range 5 {
		tx, err := s.db.Begin(ctx)
		if err != nil {
			return Chat{}, err
		}
		code := newCode()
		var c Chat
		err = tx.QueryRow(ctx, `
			INSERT INTO chats (code, owner_id, name) VALUES ($1, $2, $3)
			RETURNING code, owner_id, name, photo_url, game, created_at`,
			code, ownerID, name).
			Scan(&c.Code, &c.OwnerID, &c.Name, &c.PhotoURL, &c.Game, &c.CreatedAt)
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			tx.Rollback(ctx)
			continue // the code is taken; draw another
		}
		if err != nil {
			tx.Rollback(ctx)
			return Chat{}, err
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO chat_members (chat_code, user_id) VALUES ($1, $2)`,
			code, ownerID); err != nil {
			tx.Rollback(ctx)
			return Chat{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return Chat{}, err
		}
		return s.Get(ctx, code, ownerID)
	}
	return Chat{}, errors.New("no free chat code")
}

// Join adds userID to the chat with this code.
func (s *Store) Join(ctx context.Context, code, userID string) (Chat, error) {
	tag, err := s.db.Exec(ctx, `
		INSERT INTO chat_members (chat_code, user_id)
		SELECT code, $2 FROM chats WHERE code = $1
		ON CONFLICT DO NOTHING`, code, userID)
	if err != nil {
		return Chat{}, err
	}
	_ = tag
	return s.Get(ctx, code, userID)
}

// Get returns a chat with its members, if userID is one of them.
func (s *Store) Get(ctx context.Context, code, userID string) (Chat, error) {
	var c Chat
	err := s.db.QueryRow(ctx, `
		SELECT c.code, c.owner_id, c.name, c.photo_url, c.game, c.created_at
		FROM chats c
		JOIN chat_members m ON m.chat_code = c.code AND m.user_id = $2
		WHERE c.code = $1`, code, userID).
		Scan(&c.Code, &c.OwnerID, &c.Name, &c.PhotoURL, &c.Game, &c.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Chat{}, ErrNotMember
	}
	if err != nil {
		return Chat{}, err
	}
	rows, err := s.db.Query(ctx, `
		SELECT m.user_id, u.name, u.photo_url, m.joined_at, u.last_seen, m.read_at
		FROM chat_members m JOIN users u ON u.id = m.user_id
		WHERE m.chat_code = $1 ORDER BY m.joined_at`, code)
	if err != nil {
		return Chat{}, err
	}
	c.Members, err = pgx.CollectRows(rows, func(row pgx.CollectableRow) (Member, error) {
		var m Member
		err := row.Scan(&m.UserID, &m.Name, &m.PhotoURL, &m.JoinedAt, &m.LastSeen, &m.ReadAt)
		return m, err
	})
	return c, err
}

// List returns userID's chats, most recently active first.
func (s *Store) List(ctx context.Context, userID string) ([]Summary, error) {
	rows, err := s.db.Query(ctx, `
		SELECT c.code, c.owner_id, c.name, c.photo_url, c.game, c.created_at,
		       last.id, last.sender_id, last.sender_name, last.text,
		       last.image_url IS NOT NULL, last.audio_url IS NOT NULL,
		       last.created_at,
		       (SELECT count(*) FROM messages u
		         WHERE u.chat_code = c.code
		           AND u.sender_id IS DISTINCT FROM $1
		           AND u.created_at > coalesce(me.read_at, '-infinity'))
		FROM chat_members me
		JOIN chats c ON c.code = me.chat_code
		LEFT JOIN LATERAL (
			SELECT * FROM messages m WHERE m.chat_code = c.code
			ORDER BY m.created_at DESC, m.id DESC LIMIT 1
		) last ON true
		WHERE me.user_id = $1
		ORDER BY coalesce(last.created_at, c.created_at) DESC`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Summary, error) {
		var s Summary
		var id, senderName, text *string
		var senderID *string
		var image, voice *bool
		var at *time.Time
		err := row.Scan(&s.Code, &s.OwnerID, &s.Name, &s.PhotoURL, &s.Game, &s.CreatedAt,
			&id, &senderID, &senderName, &text, &image, &voice, &at, &s.Unread)
		if err == nil && id != nil {
			kind := "text"
			if *image {
				kind = "image"
			} else if *voice {
				kind = "voice"
			}
			s.LastMessage = &LastMessage{
				ID: *id, SenderID: senderID, SenderName: *senderName,
				Text: *text, Kind: kind, CreatedAt: *at,
			}
		}
		return s, err
	})
}

// MemberIDs returns who is in the chat, for sending them events.
func (s *Store) MemberIDs(ctx context.Context, code string) ([]string, error) {
	rows, err := s.db.Query(ctx,
		`SELECT user_id::text FROM chat_members WHERE chat_code = $1`, code)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

// ContactIDs returns everyone sharing a chat with userID, who should hear
// when they come and go.
func (s *Store) ContactIDs(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.db.Query(ctx, `
		SELECT DISTINCT other.user_id::text
		FROM chat_members me
		JOIN chat_members other ON other.chat_code = me.chat_code
		WHERE me.user_id = $1 AND other.user_id <> $1`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}

// IsMember reports whether userID is in the chat.
func (s *Store) IsMember(ctx context.Context, code, userID string) (bool, error) {
	var ok bool
	err := s.db.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM chat_members WHERE chat_code = $1 AND user_id = $2)`,
		code, userID).Scan(&ok)
	return ok, err
}

// Update changes the name, photo or game of a chat. Name and photo are
// the owner's to change; any member may update the game.
func (s *Store) Update(ctx context.Context, code, userID string, name, photoURL *string, game any) (Chat, error) {
	c, err := s.Get(ctx, code, userID)
	if err != nil {
		return Chat{}, err
	}
	if (name != nil || photoURL != nil) && c.OwnerID != userID {
		return Chat{}, ErrNotOwner
	}
	if _, err := s.db.Exec(ctx, `
		UPDATE chats SET
			name      = coalesce($2, name),
			photo_url = CASE WHEN $3::boolean THEN $4 ELSE photo_url END,
			game      = CASE WHEN $5::boolean THEN $6::jsonb ELSE game END
		WHERE code = $1`,
		code, name, photoURL != nil, photoURL, game != nil, game); err != nil {
		return Chat{}, err
	}
	return s.Get(ctx, code, userID)
}

// Remove takes memberID out of the chat. Anyone may leave; only the
// owner may remove others, and the owner can't leave their own chat.
func (s *Store) Remove(ctx context.Context, code, userID, memberID string) error {
	c, err := s.Get(ctx, code, userID)
	if err != nil {
		return err
	}
	if memberID != userID && c.OwnerID != userID {
		return ErrNotOwner
	}
	if memberID == c.OwnerID {
		return httpapi.BadRequest("The owner deletes the chat instead of leaving")
	}
	_, err = s.db.Exec(ctx,
		`DELETE FROM chat_members WHERE chat_code = $1 AND user_id = $2`,
		code, memberID)
	return err
}

// Delete removes the chat with all its messages. Owner only.
func (s *Store) Delete(ctx context.Context, code, userID string) error {
	c, err := s.Get(ctx, code, userID)
	if err != nil {
		return err
	}
	if c.OwnerID != userID {
		return ErrNotOwner
	}
	_, err = s.db.Exec(ctx, `DELETE FROM chats WHERE code = $1`, code)
	return err
}

// MarkRead records that userID has read the chat up to now.
func (s *Store) MarkRead(ctx context.Context, code, userID string) (time.Time, error) {
	var at time.Time
	err := s.db.QueryRow(ctx, `
		UPDATE chat_members SET read_at = now()
		WHERE chat_code = $1 AND user_id = $2 RETURNING read_at`,
		code, userID).Scan(&at)
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, ErrNotMember
	}
	return at, err
}
