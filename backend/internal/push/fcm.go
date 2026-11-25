// Package push sends notifications to phones through Firebase Cloud
// Messaging, which also delivers to iPhones via APNs.
package push

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"golang.org/x/oauth2/google"
)

// Notification is what a phone shows.
type Notification struct {
	Title string
	Body  string
	// Read by the app, e.g. which chat to open when tapped.
	Data map[string]string
	// On Android a newer notification with the same tag replaces the older.
	Tag string
}

// ErrDeadToken means the device token will never work again.
var ErrDeadToken = errors.New("device token is no longer valid")

// Sender delivers one notification to one device.
type Sender interface {
	Send(ctx context.Context, token string, n Notification) error
}

// FCM sends through the FCM HTTP v1 API.
type FCM struct {
	client   *http.Client
	endpoint string
}

// NewFCM signs requests with a Firebase service account key (the JSON
// file from Project settings → Service accounts).
func NewFCM(ctx context.Context, serviceAccount []byte) (*FCM, error) {
	creds, err := google.CredentialsFromJSON(ctx, serviceAccount,
		"https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return nil, fmt.Errorf("read service account: %w", err)
	}
	if creds.ProjectID == "" {
		return nil, errors.New("service account has no project_id")
	}
	return &FCM{
		client:   oauth2Client(ctx, creds),
		endpoint: "https://fcm.googleapis.com/v1/projects/" + creds.ProjectID + "/messages:send",
	}, nil
}

// NewFCMAt sends to another endpoint with a plain client; for tests.
func NewFCMAt(endpoint string, client *http.Client) *FCM {
	return &FCM{client: client, endpoint: endpoint}
}

func (f *FCM) Send(ctx context.Context, token string, n Notification) error {
	android := map[string]any{"priority": "high"}
	androidNote := map[string]any{"channel_id": "messages"}
	if n.Tag != "" {
		androidNote["tag"] = n.Tag
	}
	android["notification"] = androidNote
	apns := map[string]any{"payload": map[string]any{"aps": map[string]any{"sound": "default"}}}
	if n.Tag != "" {
		// iOS replaces notifications sharing a collapse id.
		apns["headers"] = map[string]string{"apns-collapse-id": n.Tag}
	}

	body, err := json.Marshal(map[string]any{"message": map[string]any{
		"token":        token,
		"notification": map[string]string{"title": n.Title, "body": n.Body},
		"data":         n.Data,
		"android":      android,
		"apns":         apns,
	}})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, f.endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusOK {
		return nil
	}

	var failure struct {
		Error struct {
			Status  string `json:"status"`
			Message string `json:"message"`
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	json.Unmarshal(raw, &failure)
	for _, d := range failure.Error.Details {
		// INVALID_ARGUMENT also covers a malformed message, which says
		// nothing about the device; only a bad token counts.
		if d.ErrorCode == "UNREGISTERED" ||
			(d.ErrorCode == "INVALID_ARGUMENT" && strings.Contains(failure.Error.Message, "registration token")) {
			return ErrDeadToken
		}
	}
	if res.StatusCode == http.StatusNotFound {
		return ErrDeadToken
	}
	return fmt.Errorf("fcm: %s %s", res.Status, failure.Error.Message)
}
