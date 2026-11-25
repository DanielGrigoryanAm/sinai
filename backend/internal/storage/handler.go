package storage

import (
	"context"
	"net/http"
	"strings"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

// FilesPath is where the API serves a stored file: FilesPath + key.
const FilesPath = "/v1/files/"

// URL is the API address of a stored file, for clients to load.
func URL(key *string) *string {
	if key == nil || *key == "" {
		return key
	}
	u := FilesPath + *key
	return &u
}

// ChatPrefix is where a chat's files live.
func ChatPrefix(chat string) string { return "chats/" + chat }

// KeyOf takes a key or an API file address and returns the key, checking
// it belongs to the chat. Clients may send back either.
func KeyOf(value, chat string) (string, error) {
	key := strings.TrimPrefix(value, FilesPath)
	if !strings.HasPrefix(key, ChatPrefix(chat)+"/") || strings.Contains(key, "..") {
		return "", httpapi.BadRequest("File belongs to another chat")
	}
	return key, nil
}

type Handler struct {
	storage *Storage
	// Reports whether a user is in a chat.
	isMember func(ctx context.Context, chat, userID string) (bool, error)
	userID   func(*http.Request) string
}

func NewHandler(s *Storage, isMember func(ctx context.Context, chat, userID string) (bool, error), userID func(*http.Request) string) *Handler {
	return &Handler{storage: s, isMember: isMember, userID: userID}
}

func (h *Handler) Register(mux *http.ServeMux, auth func(http.Handler) http.Handler) {
	mux.Handle("POST /v1/chats/{code}/uploads", auth(httpapi.Handler(h.upload)))
	mux.Handle("GET "+FilesPath+"{key...}", auth(httpapi.Handler(h.file)))
}

func (h *Handler) member(r *http.Request, chat string) error {
	ok, err := h.isMember(r.Context(), chat, h.userID(r))
	if err != nil {
		return err
	}
	if !ok {
		return httpapi.NotFound("Chat not found")
	}
	return nil
}

// upload hands out a URL to PUT a new photo, voice message or chat
// picture to.
func (h *Handler) upload(w http.ResponseWriter, r *http.Request) error {
	chat := strings.ToUpper(r.PathValue("code"))
	if err := h.member(r, chat); err != nil {
		return err
	}
	var body struct {
		Kind        string `json:"kind"`
		ContentType string `json:"contentType"`
	}
	if err := httpapi.ReadJSON(r, &body); err != nil {
		return err
	}
	kind, ok := map[string]Kind{"image": Image, "voice": Voice, "avatar": Avatar}[body.Kind]
	if !ok {
		return httpapi.BadRequest("Kind is image, voice or avatar")
	}
	up, err := h.storage.NewUpload(r.Context(), ChatPrefix(chat), kind, body.ContentType)
	if err != nil {
		return httpapi.BadRequest(err.Error())
	}
	return httpapi.WriteJSON(w, http.StatusOK, up)
}

// file sends a chat member on to a short-lived link to the file.
func (h *Handler) file(w http.ResponseWriter, r *http.Request) error {
	key := r.PathValue("key")
	parts := strings.SplitN(key, "/", 3)
	if len(parts) < 3 || parts[0] != "chats" {
		return httpapi.NotFound("File not found")
	}
	if err := h.member(r, parts[1]); err != nil {
		return err
	}
	u, err := h.storage.DownloadURL(r.Context(), key)
	if err != nil {
		return err
	}
	w.Header().Set("Cache-Control", "private, max-age=3000")
	http.Redirect(w, r, u, http.StatusFound)
	return nil
}
