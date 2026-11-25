#!/usr/bin/env bash
# Ships the backend to the server and (re)starts it. Run from backend/:
#   deploy/deploy.sh root@SERVER
#
# The first run creates deploy/.env on the server with fresh secrets;
# fill in API_DOMAIN and the R2 keys there, then run this again. Later
# runs keep that file, the secrets folder and the backups as they are.
set -euo pipefail

server="${1:?usage: deploy/deploy.sh user@server}"
remote=/opt/sinai/backend

cd "$(dirname "$0")/.."

echo "→ Copying code to $server:$remote"
rsync -az --delete \
  --exclude .env --exclude bin/ \
  --exclude deploy/.env --exclude deploy/secrets/ --exclude deploy/backups/ \
  ./ "$server:$remote/"

echo "→ Starting"
ssh "$server" bash -s <<EOF
set -euo pipefail
cd $remote/deploy
mkdir -p secrets backups

if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\$(openssl rand -hex 24)|" .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=\$(openssl rand -hex 48)|" .env
  chmod 600 .env
  echo
  echo "Created $remote/deploy/.env with new secrets."
  echo "Fill in API_DOMAIN and the S3_* (Cloudflare R2) values, then deploy again."
  exit 0
fi

if ! grep -q '^API_DOMAIN=.\+' .env || ! grep -q '^S3_ENDPOINT=.\+' .env; then
  echo "API_DOMAIN or S3_ENDPOINT is empty in $remote/deploy/.env" >&2
  exit 1
fi

docker compose up -d --build --remove-orphans
docker image prune -f >/dev/null

domain=\$(grep '^API_DOMAIN=' .env | cut -d= -f2)
for i in \$(seq 1 30); do
  if curl -fsS "https://\$domain/health" >/dev/null 2>&1; then
    echo "✓ Live at https://\$domain"
    exit 0
  fi
  sleep 2
done
echo "Not answering yet; see: docker compose logs api caddy" >&2
exit 1
EOF
