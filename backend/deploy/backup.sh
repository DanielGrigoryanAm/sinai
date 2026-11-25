#!/bin/sh
# Dumps the database once a day into /backups and keeps two weeks of them.
# Runs inside the backup container (see compose.yml).
while true; do
  name="/backups/sinai-$(date +%F).dump"
  if pg_dump -h postgres -U sinai -Fc sinai > "$name.tmp"; then
    mv "$name.tmp" "$name"
    echo "backup written: $name"
  else
    echo "backup failed" >&2
  fi
  # Old dumps only, by name pattern, in the backups folder only.
  find /backups -maxdepth 1 -type f -name 'sinai-*.dump' -mtime +14 -exec rm -f {} \;
  sleep 86400
done
