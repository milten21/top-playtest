#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
export COMPOSE_PROFILES=host1,host2

project="${CHECK_PROJECT:-tales-check}"
env_file="${CHECK_ENV_FILE:-.env.example}"
compose=(docker compose --project-name "$project" --env-file "$env_file")

cleanup() {
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}

fail() {
    echo "not ok - $*" >&2
    exit 1
}

pass() {
    echo "ok - $*"
}

trap 'status=$?; [ "$status" = 0 ] || "${compose[@]}" logs --no-color --tail 200 >&2 || true; cleanup' EXIT
cleanup

wait_for() {
    local seconds="$1"
    shift
    local deadline=$(( $(date +%s) + seconds ))
    until "$@" >/dev/null 2>&1; do
        [ "$(date +%s)" -lt "$deadline" ] || return 1
        sleep 2
    done
}

game_log=/var/log/tales/GameServer/log
game_servers=(game00 game01 game02 game03)

documented=$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' .env.example | sort -u)
used=$(cat compose.yaml templates/*/*.template | grep -o '\${[A-Za-z_][A-Za-z0-9_]*' | cut -c3- | sort -u)
undocumented=$(comm -13 <(echo "$documented") <(echo "$used") | paste -sd ' ' -)
[ -z "$undocumented" ] || fail ".env.example documents every variable compose.yaml and the templates use (missing: $undocumented)"
pass ".env.example documents every variable compose.yaml and the templates use"

profile_services() {
    COMPOSE_PROFILES="$1" "${compose[@]}" config --services | sort | paste -sd ' ' -
}

host1_services=$(profile_services host1)
[ "$host1_services" = "account db-init game00 game03 gate group postgres" ] || fail "the host1 profile runs postgres, db-init, account, group, gate, game00 and game03 (got: $host1_services)"
host2_services=$(profile_services host2)
[ "$host2_services" = "game01 game02" ] || fail "the host2 profile runs game01 and game02 (got: $host2_services)"
pass "the host1 profile runs $host1_services; the host2 profile runs $host2_services"

host2_env=$(mktemp -p . .host2-env.XXXXXX)
grep -vE '^(POSTGRES|ACCOUNT_DB|GROUP_ACCOUNT|GAME00_INFO|GAME03_INFO)_PASSWORD=' "$env_file" > "$host2_env"
host2_config=$(COMPOSE_PROFILES=host2 docker compose --project-name "$project" --env-file "$host2_env" config --quiet 2>&1) || { rm -f "$host2_env"; fail "the host2 profile needs no host1-only password, got:
$host2_config"; }
rm -f "$host2_env"
pass "the host2 profile needs no host1-only password"

committed_bins=$(git ls-files -- 'content/*.bin' | paste -sd ' ' -)
[ -z "$committed_bins" ] || fail "no generated server .bin tables are committed (found: $committed_bins)"
pass "no generated server .bin tables are committed"

maps_of() {
    sed -n 's/^map *= *\([^ ]*\).*/\1;/p' templates/"$1"/*.cfg.template | tr -d '\r\n'
}

"${compose[@]}" up --detach --wait --wait-timeout 600 || fail "postgres, account, group, gate and ${game_servers[*]} become healthy"
pass "postgres, account, group, gate and ${game_servers[*]} are healthy"

game_registered() {
    "${compose[@]}" exec -T "$1" grep -qF "success [MapName:$2]" "$game_log/GameServer${1#game}/GameLogin.log"
}

gate_has_map() {
    "${compose[@]}" exec -T gate grep -rqF "add [$1]  [$2] map ok" /var/log/tales/GateServer
}

for game in "${game_servers[@]}"; do
    maps=$(maps_of "$game")
    [ -n "$maps" ] || fail "$game's template lists maps"
    wait_for 120 game_registered "$game" "$maps" || fail "$game registers with GateServer with maps [$maps]"
    for map in ${maps//;/ }; do
        gate_has_map "GameServer${game#game}" "$map" || fail "GateServer adds map $map of $game"
    done
    pass "$game is registered with GateServer with maps [$maps]"
done

for game in "${game_servers[@]}"; do
    errors=$("${compose[@]}" exec -T "$game" sh -c 'cat "$1" 2>/dev/null || true' _ "$game_log/GameServer${game#game}/error.log")
    [ -z "$errors" ] || fail "$game logs no errors during startup, got:
$errors"
    pass "$game logged no errors during startup"
done

echo "content check passed"
