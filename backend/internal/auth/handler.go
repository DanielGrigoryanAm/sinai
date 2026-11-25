package auth

import (
	"errors"
	"net/http"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/users"
)

type Handler struct {
	auth  *Service
	users *users.Store
}

func NewHandler(auth *Service, users *users.Store) *Handler {
	return &Handler{auth: auth, users: users}
}

func (h *Handler) Register(mux *http.ServeMux) {
	mux.Handle("POST /v1/auth/guest", httpapi.Handler(h.guest))
	mux.Handle("POST /v1/auth/refresh", httpapi.Handler(h.refresh))
	mux.Handle("POST /v1/auth/logout", httpapi.Handler(h.logout))
}

type session struct {
	User users.User `json:"user"`
	Tokens
}

// guest creates an account without a phone or email, like the app's
// anonymous sign-in today. It can be tied to a phone number later.
func (h *Handler) guest(w http.ResponseWriter, r *http.Request) error {
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
	user, err := h.users.Create(r.Context(), name)
	if err != nil {
		return err
	}
	tokens, err := h.auth.Issue(r.Context(), user.ID)
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusCreated, session{User: user, Tokens: tokens})
}

type refreshBody struct {
	RefreshToken string `json:"refreshToken"`
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) error {
	var body refreshBody
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	tokens, err := h.auth.Refresh(r.Context(), body.RefreshToken)
	if errors.Is(err, ErrInvalidToken) {
		return httpapi.Unauthorized("Sign in again")
	}
	if err != nil {
		return err
	}
	return httpapi.WriteJSON(w, http.StatusOK, tokens)
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) error {
	var body refreshBody
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	if err := h.auth.Revoke(r.Context(), body.RefreshToken); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}
