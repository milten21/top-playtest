#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_HOST:?}" "${DEPLOY_USER:?}" "${DEPLOY_SSH_KEY:?}" "${DEPLOY_KNOWN_HOSTS:?}" "${GITHUB_SHA:?}"

mkdir -p ~/.ssh
install -m 600 /dev/null ~/.ssh/deploy_key
printf '%s\n' "$DEPLOY_SSH_KEY" > ~/.ssh/deploy_key
printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > ~/.ssh/known_hosts

ssh -i ~/.ssh/deploy_key -o BatchMode=yes -o StrictHostKeyChecking=yes "$DEPLOY_USER@$DEPLOY_HOST" bash -s -- "$GITHUB_SHA" <<'EOF'
set -euo pipefail
cd ~/tales
git fetch --quiet origin
git checkout --quiet --detach "$1"
echo "checked out $(git rev-parse HEAD)"
docker compose pull --quiet
docker compose stop
docker compose up --detach --wait --wait-timeout 600 --remove-orphans || { docker compose ps --all; exit 1; }
docker compose ps
EOF
