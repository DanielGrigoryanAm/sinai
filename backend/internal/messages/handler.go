package messages

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/chats"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/push"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/realtime"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/storage"
)

const maxTextLength = 4000

type Handler struct {
	messages *Store
	chats    *chats.Store
	events   chats.Publisher
	files    *storage.Storage
	userID   func(*http.Request) string

	// Notifies phones of new messages and reactions; nil sends nothing.
	Push *push.Service
}

func NewHandler(messages *Store, chatStore *chats.Store, events chats.Publisher, files *storage.Storage, userID func(*http.Request) string) *Handler {
	return &Handler{messages: messages, chats: chatStore, events: events, files: files, userID: userID}
}

// withURLs turns stored file keys into addresses clients can load.
func withURLs(m Message) Message {
	m.ImageURL = storage.URL(m.ImageURL)
	m.AudioURL = storage.URL(m.AudioURL)
	return m
}

func allWithURLs(list []Message) []Message {
	if list == nil {
		return []Message{}
	}
	for i := range list {
		list[i] = withURLs(list[i])
	}
	return list
}

// attach checks an uploaded file and returns its key.
func (h *Handler) attach(r *http.Request, chat string, value *string, kind storage.Kind) (*string, error) {
	if value == nil {
		return nil, nil
	}
	key, err := storage.KeyOf(*value, chat)
	if err != nil {
		return nil, err
	}
	if err := h.files.Check(r.Context(), key, kind); err != nil {
		return nil, httpapi.BadRequest(err.Error())
	}
	return &key, nil
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
	h.events.Publish(ctx, realtime.Event{Type: kind, Chat: m.ChatCode, Data: withURLs(m), To: members})
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
	return httpapi.WriteJSON(w, http.StatusOK, allWithURLs(list))
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
	return httpapi.WriteJSON(w, http.StatusOK, allWithURLs(list))
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
	if n.ImageURL, err = h.attach(r, chat, n.ImageURL, storage.Image); err != nil {
		return err
	}
	if n.AudioURL, err = h.attach(r, chat, n.AudioURL, storage.Voice); err != nil {
		return err
	}
	m, err := h.messages.Send(r.Context(), chat, h.userID(r), n)
	if err != nil {
		return err
	}
	h.notify(r.Context(), "message.created", m)
	h.pushMessage(r.Context(), m)
	return httpapi.WriteJSON(w, http.StatusCreated, withURLs(m))
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
	return httpapi.WriteJSON(w, http.StatusOK, withURLs(m))
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
	// Its photo or voice file goes with it.
	for _, key := range []*string{m.ImageURL, m.AudioURL} {
		if key != nil {
			h.files.Delete(context.WithoutCancel(r.Context()), *key)
		}
	}
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

// pushMessage tells everyone else in the chat about a new message.
func (h *Handler) pushMessage(ctx context.Context, m Message) {
	if h.Push == nil || m.SenderID == nil {
		return
	}
	c, err := h.chats.Get(ctx, m.ChatCode, *m.SenderID)
	if err != nil {
		return
	}
	var to []string
	for _, member := range c.Members {
		if member.UserID != *m.SenderID {
			to = append(to, member.UserID)
		}
	}
	what := push.Describe(m.Text, m.ImageURL != nil, m.AudioURL != nil)
	h.Push.ToUsers(to, push.NewMessage(c.Code, c.Name, m.SenderName, what))
}

// pushReaction tells the author when someone else reacts to their message.
func (h *Handler) pushReaction(ctx context.Context, m Message, reactorID, emoji string) {
	if h.Push == nil || m.SenderID == nil || *m.SenderID == reactorID {
		return
	}
	c, err := h.chats.Get(ctx, m.ChatCode, reactorID)
	if err != nil {
		return
	}
	var reactor string
	for _, member := range c.Members {
		if member.UserID == reactorID {
			reactor = member.Name
		}
	}
	quoted := push.Describe(m.Text, m.ImageURL != nil, m.AudioURL != nil)
	h.Push.ToUsers([]string{*m.SenderID},
		push.Reaction(c.Code, c.Name, m.ID, reactor, emoji, quoted))
}

func (h *Handler) setReaction(w http.ResponseWriter, r *http.Request, emoji string) error {
	chat, err := h.member(r)
	if err != nil {
		return err
	}
	me := h.userID(r)
	previous := ""
	if old, err := h.messages.get(r.Context(), r.PathValue("id")); err == nil {
		previous = old.Reactions[me]
	}
	m, err := h.messages.React(r.Context(), chat, r.PathValue("id"), me, emoji)
	if err != nil {
		return err
	}
	// Only a new or changed reaction notifies, not removing one.
	if emoji != "" && emoji != previous {
		h.pushReaction(r.Context(), m, me, emoji)
	}
	h.notify(r.Context(), "message.updated", m)
	return httpapi.WriteJSON(w, http.StatusOK, withURLs(m))
}
