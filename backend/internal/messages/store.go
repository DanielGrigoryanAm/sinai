// Package messages stores what is said in chats.
package messages

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

type Message struct {
	ID            string            `json:"id"`
	ChatCode      string            `json:"chatCode"`
	SenderID      *string           `json:"senderId"`
	SenderName    string            `json:"senderName"`
	Text          string            `json:"text"`
	ImageURL      *string           `json:"imageUrl"`
	ImageWidth    *int              `json:"imageWidth"`
	ImageHeight   *int              `json:"imageHeight"`
	AudioURL      *string           `json:"audioUrl"`
	AudioMs       *int              `json:"audioMs"`
	ReplyTo       *Reply            `json:"replyTo"`
	ForwardedFrom *string           `json:"forwardedFrom"`
	Reactions     map[string]string `json:"reactions"` // user id → emoji
	CreatedAt     time.Time         `json:"createdAt"`
	EditedAt      *time.Time        `json:"editedAt"`
}

// Reply is the message being answered, as quoted above the answer.
type Reply struct {
	ID         string `json:"id"`
	SenderName string `json:"senderName"`
	Text       string `json:"text"`
	Kind       string `json:"kind"`
}

// New is a message to send.
type New struct {
	Text          string  `json:"text"`
	ImageURL      *string `json:"imageUrl"`
	ImageWidth    *int    `json:"imageWidth"`
	ImageHeight   *int    `json:"imageHeight"`
	AudioURL      *string `json:"audioUrl"`
	AudioMs       *int    `json:"audioMs"`
	ReplyTo       *string `json:"replyTo"`
	ForwardedFrom *string `json:"forwardedFrom"`
}

var ErrNotFound = httpapi.NotFound("Message not found")

type Store struct{ db *pgxpool.Pool }

func NewStore(db *pgxpool.Pool) *Store { return &Store{db: db} }

const selectMessage = `
	SELECT m.id, m.chat_code, m.sender_id, m.sender_name, m.text,
	       m.image_url, m.image_width, m.image_height, m.audio_url, m.audio_ms,
	       r.id, r.sender_name, r.text, r.image_url IS NOT NULL, r.audio_url IS NOT NULL,
	       m.forwarded_from,
	       coalesce((SELECT jsonb_object_agg(x.user_id, x.emoji)
	                 FROM message_reactions x WHERE x.message_id = m.id), '{}'),
	       m.created_at, m.edited_at
	FROM messages m
	LEFT JOIN messages r ON r.id = m.reply_to`

func scan(row pgx.Row) (Message, error) {
	var m Message
	var replyID, replyName, replyText *string
	var replyImage, replyVoice *bool
	err := row.Scan(&m.ID, &m.ChatCode, &m.SenderID, &m.SenderName, &m.Text,
		&m.ImageURL, &m.ImageWidth, &m.ImageHeight, &m.AudioURL, &m.AudioMs,
		&replyID, &replyName, &replyText, &replyImage, &replyVoice,
		&m.ForwardedFrom, &m.Reactions, &m.CreatedAt, &m.EditedAt)
	if err != nil {
		return Message{}, err
	}
	if replyID != nil {
		kind := "text"
		if *replyImage {
			kind = "image"
		} else if *replyVoice {
			kind = "voice"
		}
		m.ReplyTo = &Reply{ID: *replyID, SenderName: *replyName, Text: *replyText, Kind: kind}
	}
	return m, nil
}

func (s *Store) get(ctx context.Context, id string) (Message, error) {
	m, err := scan(s.db.QueryRow(ctx, selectMessage+` WHERE m.id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return Message{}, ErrNotFound
	}
	return m, err
}

// Send adds a message from senderID to the chat.
func (s *Store) Send(ctx context.Context, chat, senderID string, n New) (Message, error) {
	var id string
	err := s.db.QueryRow(ctx, `
		INSERT INTO messages (chat_code, sender_id, sender_name, text,
			image_url, image_width, image_height, audio_url, audio_ms,
			reply_to, forwarded_from)
		SELECT $1, u.id, u.name, $3, $4, $5, $6, $7, $8,
		       -- Only a message of the same chat can be answered.
		       (SELECT id FROM messages WHERE id = $9 AND chat_code = $1),
		       $10
		FROM users u WHERE u.id = $2
		RETURNING id`,
		chat, senderID, n.Text, n.ImageURL, n.ImageWidth, n.ImageHeight,
		n.AudioURL, n.AudioMs, n.ReplyTo, n.ForwardedFrom).Scan(&id)
	if err != nil {
		return Message{}, err
	}
	return s.get(ctx, id)
}

// Page returns up to limit messages of the chat older than the message
// before (or the newest ones if before is empty), newest first.
func (s *Store) Page(ctx context.Context, chat, before string, limit int) ([]Message, error) {
	rows, err := s.db.Query(ctx, selectMessage+`
		WHERE m.chat_code = $1
		  AND ($2 = '' OR (m.created_at, m.id) <
		       (SELECT created_at, id FROM messages WHERE id::text = $2))
		ORDER BY m.created_at DESC, m.id DESC
		LIMIT $3`, chat, before, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Message, error) {
		return scan(row)
	})
}

// Search finds messages of the chat containing query, newest first.
func (s *Store) Search(ctx context.Context, chat, query string, limit int) ([]Message, error) {
	rows, err := s.db.Query(ctx, selectMessage+`
		WHERE m.chat_code = $1 AND m.text ILIKE '%' || $2 || '%'
		ORDER BY m.created_at DESC, m.id DESC
		LIMIT $3`, chat, escapeLike(query), limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (Message, error) {
		return scan(row)
	})
}

func escapeLike(s string) string {
	out := make([]rune, 0, len(s))
	for _, r := range s {
		if r == '%' || r == '_' || r == '\\' {
			out = append(out, '\\')
		}
		out = append(out, r)
	}
	return string(out)
}

// Edit changes the text of the sender's own message.
func (s *Store) Edit(ctx context.Context, chat, id, userID, text string) (Message, error) {
	tag, err := s.db.Exec(ctx, `
		UPDATE messages SET text = $4, edited_at = now()
		WHERE id = $1 AND chat_code = $2 AND sender_id = $3`,
		id, chat, userID, text)
	if err != nil {
		return Message{}, err
	}
	if tag.RowsAffected() == 0 {
		return Message{}, ErrNotFound
	}
	return s.get(ctx, id)
}

// Delete removes the sender's own message. The chat owner may delete any.
func (s *Store) Delete(ctx context.Context, chat, id, userID string) (Message, error) {
	m, err := s.get(ctx, id)
	if err != nil || m.ChatCode != chat {
		return Message{}, ErrNotFound
	}
	tag, err := s.db.Exec(ctx, `
		DELETE FROM messages m USING chats c
		WHERE m.id = $1 AND c.code = m.chat_code
		  AND (m.sender_id = $2 OR c.owner_id = $2)`, id, userID)
	if err != nil {
		return Message{}, err
	}
	if tag.RowsAffected() == 0 {
		return Message{}, ErrNotFound
	}
	return m, nil
}

// React sets userID's reaction to a message, or clears it if emoji is "".
func (s *Store) React(ctx context.Context, chat, id, userID, emoji string) (Message, error) {
	m, err := s.get(ctx, id)
	if err != nil || m.ChatCode != chat {
		return Message{}, ErrNotFound
	}
	if emoji == "" {
		_, err = s.db.Exec(ctx,
			`DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2`,
			id, userID)
	} else {
		_, err = s.db.Exec(ctx, `
			INSERT INTO message_reactions (message_id, user_id, emoji)
			VALUES ($1, $2, $3)
			ON CONFLICT (message_id, user_id)
			DO UPDATE SET emoji = excluded.emoji, created_at = now()`,
			id, userID, emoji)
	}
	if err != nil {
		return Message{}, err
	}
	return s.get(ctx, id)
}
