package push

import (
	"net/http"
	"strings"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

type Handler struct {
	push   *Service
	userID func(*http.Request) string
}

func NewHandler(push *Service, userID func(*http.Request) string) *Handler {
	return &Handler{push: push, userID: userID}
}

func (h *Handler) Register(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.Handle("PUT /v1/devices", auth(httpapi.Handler(h.save)))
	mux.Handle("DELETE /v1/devices/{token}", auth(httpapi.Handler(h.forget)))
}

// save registers this device's push token; apps call it on start and
// whenever FCM hands them a new token.
func (h *Handler) save(w http.ResponseWriter, r *http.Request) error {
	var body struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	body.Token = strings.TrimSpace(body.Token)
	if body.Token == "" || len(body.Token) > 4096 {
		return httpapi.BadRequest("Missing token")
	}
	switch body.Platform {
	case "ios", "android", "web":
	default:
		return httpapi.BadRequest("Platform is ios, android or web")
	}
	if err := h.push.SaveDevice(r.Context(), h.userID(r), body.Token, body.Platform); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (h *Handler) forget(w http.ResponseWriter, r *http.Request) error {
	if err := h.push.ForgetDevice(r.Context(), h.userID(r), r.PathValue("token")); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}
