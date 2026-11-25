package push

import (
	"context"
	"net/http"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

func oauth2Client(ctx context.Context, creds *google.Credentials) *http.Client {
	return oauth2.NewClient(context.WithoutCancel(ctx), creds.TokenSource)
}
