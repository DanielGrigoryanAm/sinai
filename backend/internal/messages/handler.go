package messages

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/chats"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/realtime"
)

const maxTextLength = 4000

type Handler struct {
	messages *Store
	chats    *chats.Store
	events   chats.Publisher
	userID   func(*http.Request) string
}

func NewHandler(messages *Store, chatStore *chats.Store, events chats.Publisher, userID func(*http.Request) string) *Handler {
	return &Handler{messages: messages, chats: chatStore, events: events, userID: userID}
}

func (h *Handler) Register(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	route := func(pattern string, fn httpapi.Handler) { mux.Handle(pattern, auth(fn)) }
	route("GET /v1/chats/{code}/messages", h.page)
	route("POST /v1/chats/{code}/messages", h.send)
	route("GET /v1/chats/{code}/messages/search", h.search)
	route("PATCH /v1/chats/{code}/messages/{id}", h.edit)
	route("DELETE /v1/chats/{code}/messages/{id}", h.delete)
	route("PUT /v1/chats/{code}/messages/{id}/reaction", h.react)
	route("DELETE /v1/chats/{code}/messages/{id}/reaction", h.unreact)
}

// member returns the chat code of the request, checking the user is in it.
func (h *Handler) member(r *http.Request) (string, error) {
	chat := strings.ToUpper(r.PathValue("code"))
	ok, err := h.chats.IsMember(r.Context(), chat, h.userID(r))
	if err != nil {
		return "", err
	}
	if !ok {
		return "", chats.ErrNotMember
	}
	return chat, nil
}

// notify sends a message event to everyone in its chat.
func (h *Handler) notify(ctx context.Context, kind string, m Message) {
	members, err := h.chats.MemberIDs(ctx, m.ChatCode)
	if err != nil {
		return
	}
	h.events.Publish(ctx, realtime.Event{Type: kind, Chat: m.ChatCode, Data: m, To: members})
}

func limit(r *http.Request) int {
	n, err := strconv.Atoi(r.URL.Query().Get("limit"))
	if err != nil || n <= 0 {
		return 30
	}
	return min(n, 100)
}

func (h *Handler) page(w http.ResponseWriter, r *http.Request) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	list, err := h.messages.Page(r.Context(), chat, r.URL.Query().Get("before"), limit(r))
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusOK, nonNil(list))
}

func (h *Handler) search(w http.ResponseWriter, r *http.Request) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		return httpapi.WriteJSON(w, http.StatusOK, []Message{})
	}
	list, err := h.messages.Search(r.Context(), chat, q, limit(r))
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusOK, nonNil(list))
}

func nonNil(list []Message) []Message {
	if list == nil {
		return []Message{}
	}
	return list
}

func checkText(text string) error {
	if utf8.RuneCountInString(text) > maxTextLength {
		return httpapi.BadRequest("Message is too long")
	}
	return nil
}

func (h *Handler) send(w http.ResponseWriter, r *http.Request) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	var n New
	if err := httpapi.ReadJSON(r, &n); err != nil {
		return err
	}
	n.Text = strings.TrimSpace(n.Text)
	if n.Text == "" && n.ImageURL == nil && n.AudioURL == nil {
		return httpapi.BadRequest("Message is empty")
	}
	if err := checkText(n.Text); err != nil {
		return err
	}
	m, err := h.messages.Send(r.Context(), chat, h.userID(r), n)
	if err != nil {
		return err
	}
	h.notify(r.Context(), "message.created", m)
	return httpapi.WriteJSON(w, http.StatusCreated, m)
}

func (h *Handler) edit(w http.ResponseWriter, r *http.Request) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	var body struct {
		Text string `json:"text"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	if err := checkText(body.Text); err != nil {
		return err
	}
	m, err := h.messages.Edit(r.Context(), chat, r.PathValue("id"), h.userID(r), strings.TrimSpace(body.Text))
	if err != nil {
		return err
	}
	h.notify(r.Context(), "message.updated", m)
	return httpapi.WriteJSON(w, http.StatusOK, m)
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	m, err := h.messages.Delete(r.Context(), chat, r.PathValue("id"), h.userID(r))
	if err != nil {
		return err
	}
	h.notify(r.Context(), "message.deleted", m)
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (h *Handler) react(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Emoji string `json:"emoji"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	if body.Emoji == "" || utf8.RuneCountInString(body.Emoji) > 8 {
		return httpapi.BadRequest("Pick one emoji")
	}
	return h.setReaction(w, r, body.Emoji)
}

func (h *Handler) unreact(w http.ResponseWriter, r *http.Request) error {
	return h.setReaction(w, r, "")
}

func (h *Handler) setReaction(w http.ResponseWriter, r *http.Request, emoji string) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	m, err := h.messages.React(r.Context(), chat, r.PathValue("id"), h.userID(r), emoji)
	if err != nil {
		return err
	}
	h.notify(r.Context(), "message.updated", m)
	return httpapi.WriteJSON(w, http.StatusOK, m)
}
