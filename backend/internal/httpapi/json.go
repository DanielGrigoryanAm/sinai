// Package httpapi holds the HTTP plumbing shared by the handlers.
package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
)

// Error is a failure the client should see, with its HTTP status.
type Error struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *Error) Error() string { return e.Message }

func BadRequest(msg string) *Error {
	return &Error{http.StatusBadRequest, "bad_request", msg}
}

func Unauthorized(msg string) *Error {
	return &Error{http.StatusUnauthorized, "unauthorized", msg}
}

func NotFound(msg string) *Error {
	return &Error{http.StatusNotFound, "not_found", msg}
}

// Handler is an http.HandlerFunc that returns its error instead of
// writing it.
type Handler func(w http.ResponseWriter, r *http.Request) error

func (h Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	err := h(w, r)
	if err == nil {
		return
	}
	var apiErr *Error
	if !errors.As(err, &apiErr) {
		slog.Error("request failed", "method", r.Method, "path", r.URL.Path, "err", err)
		apiErr = &Error{http.StatusInternalServerError, "internal", "Something went wrong"}
	}
	WriteJSON(w, apiErr.Status, map[string]any{"error": apiErr})
}

func WriteJSON(w http.ResponseWriter, status int, body any) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	return json.NewEncoder(w).Encode(body)
}

// ReadJSON decodes a request body of at most 1 MB into dst.
func ReadJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return BadRequest("Invalid JSON body")
	}
	return nil
}
