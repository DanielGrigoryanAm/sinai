# Deploying the Sinai backend

One VPS runs everything: Caddy (HTTPS), the API, Postgres, Redis and a
nightly backup. Photos and voice messages live in Cloudflare R2.

```
phone ──HTTPS/WSS──▶ Caddy :443 ──▶ api :8080 ──▶ Postgres, Redis
   └──── signed URLs ────────────────────────────▶ Cloudflare R2
```

## 1. Server

1. Create a Hetzner Cloud account and a server: **CX22**, **Ubuntu 24.04**,
   location close to your users. Add your SSH key while creating it (if you
   have none: `ssh-keygen -t ed25519`, then paste `~/.ssh/id_ed25519.pub`).
2. Prepare it (Docker, firewall, security updates), from `backend/`:

   ```bash
   ssh root@SERVER_IP 'bash -s' < deploy/setup-server.sh
   ```

## 2. Media storage (Cloudflare R2)

1. Cloudflare dashboard → **R2** → create bucket **sinai**.
2. **Manage R2 API tokens** → create a token with **Object Read & Write**
   on that bucket. Note the Access Key ID, Secret Access Key and the
   endpoint `<account id>.r2.cloudflarestorage.com` (without `https://`).

## 3. First deploy

```bash
deploy/deploy.sh root@SERVER_IP
```

The first run copies the code and creates `/opt/sinai/backend/deploy/.env`
on the server with a new database password and JWT secret. Fill in the
rest there:

```bash
ssh root@SERVER_IP nano /opt/sinai/backend/deploy/.env
```

- `API_DOMAIN`: until there's a domain, the server IP with dashes on
  sslip.io, e.g. `203-0-113-7.sslip.io`. It gets a real certificate.
- `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`: from step 2.

Then deploy again; it waits until the API answers:

```bash
deploy/deploy.sh root@SERVER_IP
```

The app's **baseURL** is `https://API_DOMAIN` and the live socket
`wss://API_DOMAIN/v1/ws`.

## 4. Pushes

Firebase console → Project settings → Service accounts → **Generate new
private key**. Then:

```bash
scp firebase-key.json root@SERVER_IP:/opt/sinai/backend/deploy/secrets/fcm.json
ssh root@SERVER_IP "sed -i 's/^FCM_CREDENTIALS_FILE=.*/FCM_CREDENTIALS_FILE=1/' /opt/sinai/backend/deploy/.env"
deploy/deploy.sh root@SERVER_IP
```

## 5. When the domain is bought

Add a DNS **A record** `api` → `SERVER_IP` (on Cloudflare, leave the proxy
off: grey cloud). Set `API_DOMAIN=api.yourdomain.com` in the server's
`.env` and deploy. Caddy fetches the new certificate itself; the app's
baseURL changes to `https://api.yourdomain.com`.

## Everyday

| What | How |
|------|-----|
| Ship a new version | `deploy/deploy.sh root@SERVER_IP` |
| Logs | `ssh root@SERVER_IP 'cd /opt/sinai/backend/deploy && docker compose logs -f api'` |
| Status | `ssh root@SERVER_IP 'cd /opt/sinai/backend/deploy && docker compose ps'` |
| Copy backups home | `rsync -av root@SERVER_IP:/opt/sinai/backend/deploy/backups/ ~/sinai-backups/` |
| Restore a backup | `docker compose exec -T postgres pg_restore -U sinai -d sinai --clean < backups/sinai-DATE.dump` |

Backups are taken every night and kept for 14 days on the server; copy
them off it now and then, since a lost server takes them along.
