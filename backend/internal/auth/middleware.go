package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/httpapi"
)

type ctxKey struct{}

// UserID is the signed-in user of a request that went through Require.
func UserID(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}

// Require lets a request through only with a valid access token in its
// "Authorization: Bearer ..." header.
func (s *Service) Require(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		userID, err := s.Verify(token)
		if !ok || err != nil {
			httpapi.Handler(func(http.ResponseWriter, *http.Request) error {
				return httpapi.Unauthorized("Sign in again")
			}).ServeHTTP(w, r)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, userID)))
	})
}
