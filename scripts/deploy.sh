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
previous=$(cat ~/.tales-deployed 2>/dev/null || true)
git checkout --quiet --detach "$1"
echo "checked out $(git rev-parse HEAD)"
changed=$(git diff --name-only "$previous" HEAD 2>/dev/null) || changed=
if [ -n "$changed" ] && ! grep -qv '^web/signup/' <<<"$changed"; then
  if grep -qx signup <<<"$(docker compose config --services)"; then
    docker compose up --detach --build --no-deps --wait signup || { docker compose ps --all; exit 1; }
  fi
else
  docker compose pull --quiet
  docker compose stop
  docker compose up --detach --build --wait --wait-timeout 600 --remove-orphans || { docker compose ps --all; exit 1; }
fi
git rev-parse HEAD > ~/.tales-deployed
docker compose ps
EOF
