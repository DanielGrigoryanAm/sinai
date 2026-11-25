package chats

import (
	"context"
	"net/http"
	"strings"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/realtime"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/users"
)

// Publisher sends live events to clients.
type Publisher interface {
	Publish(ctx context.Context, e realtime.Event)
}

type Handler struct {
	chats  *Store
	events Publisher
	userID func(*http.Request) string
}

func NewHandler(chats *Store, events Publisher, userID func(*http.Request) string) *Handler {
	return &Handler{chats: chats, events: events, userID: userID}
}

func (h *Handler) Register(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	route := func(pattern string, fn httpapi.Handler) { mux.Handle(pattern, auth(fn)) }
	route("GET /v1/chats", h.list)
	route("POST /v1/chats", h.create)
	route("GET /v1/chats/{code}", h.get)
	route("PATCH /v1/chats/{code}", h.update)
	route("DELETE /v1/chats/{code}", h.delete)
	route("POST /v1/chats/{code}/join", h.join)
	route("POST /v1/chats/{code}/read", h.read)
	route("DELETE /v1/chats/{code}/members/{userId}", h.removeMember)
}

func code(r *http.Request) string { return strings.ToUpper(r.PathValue("code")) }

// changed tells the members a chat was updated.
func (h *Handler) changed(ctx context.Context, c Chat) {
	to := make([]string, len(c.Members))
	for i, m := range c.Members {
		to[i] = m.UserID
	}
	h.events.Publish(ctx, realtime.Event{Type: "chat.updated", Chat: c.Code, Data: c, To: to})
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) error {
	chats, err := h.chats.List(r.Context(), h.userID(r))
	if err != nil {
		return err
	}
	if chats == nil {
		chats = []Summary{}
	}
	return httpapi.WriteJSON(w, http.StatusOK, chats)
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Name string `json:"name"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	name, err := users.CleanName(body.Name)
	if err != nil {
		return err
	}
	c, err := h.chats.Create(r.Context(), h.userID(r), name)
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusCreated, c)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) error {
	c, err := h.chats.Get(r.Context(), code(r), h.userID(r))
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusOK, c)
}

func (h *Handler) join(w http.ResponseWriter, r *http.Request) error {
	c, err := h.chats.Join(r.Context(), code(r), h.userID(r))
	if err != nil {
		return err
	}
	h.changed(r.Context(), c)
	return httpapi.WriteJSON(w, http.StatusOK, c)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Name     *string `json:"name"`
		PhotoURL *string `json:"photoUrl"`
		Game     any     `json:"game"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	if body.Name != nil {
		name, err := users.CleanName(*body.Name)
		if err != nil {
			return err
		}
		if name == "" {
			return httpapi.BadRequest("Name can't be empty")
		}
		body.Name = &name
	}
	c, err := h.chats.Update(r.Context(), code(r), h.userID(r), body.Name, body.PhotoURL, body.Game)
	if err != nil {
		return err
	}
	h.changed(r.Context(), c)
	return httpapi.WriteJSON(w, http.StatusOK, c)
}

func (h *Handler) removeMember(w http.ResponseWriter, r *http.Request) error {
	ctx, chat, me := r.Context(), code(r), h.userID(r)
	member := r.PathValue("userId")
	if member == "me" {
		member = me
	}
	if err := h.chats.Remove(ctx, chat, me, member); err != nil {
		return err
	}
	h.events.Publish(ctx, realtime.Event{Type: "chat.removed", Chat: chat, To: []string{member}})
	// Tell those still in the chat; read it as one of them.
	if ids, err := h.chats.MemberIDs(ctx, chat); err == nil && len(ids) > 0 {
		if c, err := h.chats.Get(ctx, chat, ids[0]); err == nil {
			h.changed(ctx, c)
		}
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) error {
	ctx, chat := r.Context(), code(r)
	members, err := h.chats.MemberIDs(ctx, chat)
	if err != nil {
		return err
	}
	if err := h.chats.Delete(ctx, chat, h.userID(r)); err != nil {
		return err
	}
	h.events.Publish(ctx, realtime.Event{Type: "chat.deleted", Chat: chat, To: members})
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (h *Handler) read(w http.ResponseWriter, r *http.Request) error {
	ctx, chat, me := r.Context(), code(r), h.userID(r)
	at, err := h.chats.MarkRead(ctx, chat, me)
	if err != nil {
		return err
	}
	members, err := h.chats.MemberIDs(ctx, chat)
	if err != nil {
		return err
	}
	h.events.Publish(ctx, realtime.Event{
		Type: "chat.read", Chat: chat, To: members,
		Data: map[string]any{"userId": me, "readAt": at},
	})
	w.WriteHeader(http.StatusNoContent)
	return nil
}
