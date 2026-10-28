#!/bin/sh
# Starts the subscription proxy on its own Postgres database with the settings in config.yaml.
set -eu

: "${PGSTORE_DSN:?PGSTORE_DSN must name the proxy's own Postgres database}"
: "${MANAGEMENT_PASSWORD:?MANAGEMENT_PASSWORD must be set}"
: "${PROXY_CLIENT_KEY:?PROXY_CLIENT_KEY must be set}"

case "$PROXY_CLIENT_KEY" in
  *[!A-Za-z0-9_-]*) echo "PROXY_CLIENT_KEY may hold only letters, digits, - and _" >&2; exit 1 ;;
esac

sed "s/__PROXY_CLIENT_KEY__/$PROXY_CLIENT_KEY/" /CLIProxyAPI/firefight-config.yaml > /CLIProxyAPI/config.example.yaml

# The proxy keeps its settings in its database once seeded and seeds only an empty one.
# Clearing the stored copy makes every start run the settings in this repository.
psql "$PGSTORE_DSN" -v ON_ERROR_STOP=1 -q -c "CREATE TABLE IF NOT EXISTS config_store (id TEXT PRIMARY KEY, content TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())" -c "DELETE FROM config_store WHERE id = 'config'"

exec ./CLIProxyAPI "$@"
