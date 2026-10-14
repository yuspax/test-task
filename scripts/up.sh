#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is unavailable. Start Docker Desktop and try again." >&2
  exit 1
fi

docker compose up --build --detach --wait --wait-timeout 120
python3 scripts/smoke.py "http://localhost:${HTTP_PORT:-8080}"
