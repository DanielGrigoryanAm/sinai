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

Authenticated requests send `Authorization: Bearer <accessToken>`. Access
tokens last 15 minutes; refresh tokens 30 days and work once each.
