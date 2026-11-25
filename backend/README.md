# Sinai backend

Go API for the Sinai messenger: PostgreSQL for data, Redis for presence
and fan-out between servers, S3-compatible storage for media.

## Run locally

```bash
colima start          # or any Docker runtime
docker compose up -d  # Postgres, Redis, S3 storage
cp .env.example .env  # once
go run ./cmd/server   # http://localhost:8080
```

The schema in `internal/db/migrations` is applied on start.

## API so far

| Method | Path               | Auth | Does                                   |
|--------|--------------------|------|----------------------------------------|
| GET    | `/health`          |      | Liveness check                         |
| POST   | `/v1/auth/guest`   |      | New account `{name}` → user and tokens |
| POST   | `/v1/auth/refresh` |      | `{refreshToken}` → new token pair      |
| POST   | `/v1/auth/logout`  |      | `{refreshToken}` → ends that session   |
| GET    | `/v1/me`           | ✓    | The signed-in user                     |
| PATCH  | `/v1/me`           | ✓    | `{name}` → renames                     |

| GET    | `/v1/chats`        | ✓    | My chats: last message, unread count   |
| POST   | `/v1/chats`        | ✓    | `{name}` → new chat with a code        |
| GET    | `/v1/chats/{code}` | ✓    | Chat with members                      |
| PATCH  | `/v1/chats/{code}` | ✓    | `{name, photoUrl}` (owner), `{game}`   |
| DELETE | `/v1/chats/{code}` | ✓    | Deletes the chat (owner)               |
| POST   | `/v1/chats/{code}/join` | ✓ | Joins by code                        |
| POST   | `/v1/chats/{code}/read` | ✓ | Marks read up to now                 |
| DELETE | `/v1/chats/{code}/members/{id or me}` | ✓ | Leave / remove (owner) |
| GET    | `/v1/chats/{code}/messages?before=&limit=` | ✓ | History, newest first |
| POST   | `/v1/chats/{code}/messages` | ✓ | Send text, photo, voice, reply   |
| GET    | `/v1/chats/{code}/messages/search?q=` | ✓ | Search text            |
| PATCH  | `/v1/chats/{code}/messages/{id}` | ✓ | Edit own `{text}`           |
| DELETE | `/v1/chats/{code}/messages/{id}` | ✓ | Delete own (owner: any)     |
| PUT    | `/v1/chats/{code}/messages/{id}/reaction` | ✓ | `{emoji}`          |
| DELETE | `/v1/chats/{code}/messages/{id}/reaction` | ✓ | Remove reaction    |
| POST   | `/v1/chats/{code}/uploads` | ✓ | `{kind, contentType}` → signed PUT URL and key |
| GET    | `/v1/files/{key}`  | ✓    | Redirects a chat member to the file    |
| PUT    | `/v1/devices`      | ✓    | `{token, platform}` → push this phone  |
| DELETE | `/v1/devices/{token}` | ✓ | Stop pushing this phone (sign-out)     |
| GET    | `/v1/ws`           | ✓    | WebSocket of live events               |

Authenticated requests send `Authorization: Bearer <accessToken>`. Access
tokens last 15 minutes; refresh tokens 30 days and work once each.

## Live events

`/v1/ws` pushes JSON events `{type, chat, data}`: `message.created`,
`message.updated`, `message.deleted`, `chat.updated`, `chat.read`,
`chat.removed`, `chat.deleted`, `typing`, `presence`
(`{userId, online, lastSeen}`, to everyone sharing a chat). Clients send
`{"type":"typing","chat":"CODE"}` while typing. Events go through Redis,
so they reach users on any server instance.

## Pushes

Sent through FCM, which also reaches iPhones via the APNs key already set
up in Firebase. Set `FCM_CREDENTIALS_FILE` to a Firebase service account
key; without it pushes are off. Phones get pushes for new messages,
reactions to their messages, game invites, their turn and game results.
Tokens FCM reports as gone are forgotten.

## Smoke test

Runs everything end to end, with a stand-in for FCM on :9099:

```bash
FCM_TEST_ENDPOINT=http://localhost:9099/send go run ./cmd/server &
go run ./cmd/smoke
```

## Files

1. `POST /v1/chats/{code}/uploads` with `kind` (`image`, `voice` or
   `avatar`) and the file's `contentType`.
2. `PUT` the bytes to `uploadUrl` within 15 minutes.
3. Send a message with `imageUrl` / `audioUrl` set to the `key`, or set
   the chat's `photoUrl` to it. The API checks the file is there and not
   too big (photos 15 MB, voice 25 MB, chat pictures 5 MB).

Messages and chats come back with `/v1/files/...` addresses; loading one
with the access token redirects to a short-lived storage link. Files go
when their message or chat is deleted.
