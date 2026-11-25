package users

import (
	"net/http"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

type Handler struct {
	users *Store
	// Reads the signed-in user from the request.
	userID func(*http.Request) string
}

func NewHandler(users *Store, userID func(*http.Request) string) *Handler {
	return &Handler{users: users, userID: userID}
}

// Register adds the routes; requireAuth guards them.
func (h *Handler) Register(mux *http.ServeMux, requireAuth func(http.Handler) http.Handler) {
	mux.Handle("GET /v1/me", requireAuth(httpapi.Handler(h.me)))
	mux.Handle("PATCH /v1/me", requireAuth(httpapi.Handler(h.update)))
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) error {
	user, err := h.users.Get(r.Context(), h.userID(r))
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusOK, user)
}

func (h *Handler) update(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Name *string `json:"name"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	if body.Name == nil {
		return h.me(w, r)
	}
	name, err := CleanName(*body.Name)
	if err != nil {
		return err
	}
	user, err := h.users.Rename(r.Context(), h.userID(r), name)
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusOK, user)
}
