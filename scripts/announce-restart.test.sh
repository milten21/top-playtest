#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/announce-restart.sh"
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT

cat > "$stubs/docker" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  config) printf '%s\n' $STUB_SERVICES ;;
  exec) echo "notice ${*: -1}" >> "$STUB_LOG"; [ -z "${STUB_EXEC_FAIL:-}" ] ;;
esac
EOF
cat > "$stubs/sleep" <<'EOF'
#!/usr/bin/env bash
echo "sleep $1" >> "$STUB_LOG"
EOF
chmod +x "$stubs/docker" "$stubs/sleep"

fail() {
    echo "not ok - $*" >&2
    exit 1
}

run() {
    export STUB_LOG="$stubs/log"
    : > "$STUB_LOG"
    PATH="$stubs:$PATH" "$script" "$@" 2> "$stubs/stderr"
}

expect_log() {
    local got
    got=$(cat "$stubs/log")
    [ "$got" = "$1" ] || fail "$2, got:
$got"
    echo "ok - $2"
}

STUB_SERVICES="game00 game03" run 1m 30s
expect_log "notice Server restarting in 1 minute.
sleep 30
notice Server restarting in 30 seconds.
sleep 30" "host #1 announces each step and sleeps until the restart"

STUB_SERVICES="game00" run 15m 10m 5m 1m 1s
expect_log "notice Server restarting in 15 minutes.
sleep 300
notice Server restarting in 10 minutes.
sleep 300
notice Server restarting in 5 minutes.
sleep 240
notice Server restarting in 1 minute.
sleep 59
notice Server restarting in 1 second.
sleep 1" "minutes and seconds wording is right, singular included"

STUB_SERVICES="game01 game02" run 1m 30s
expect_log "sleep 30
sleep 30" "a host without game00 only sleeps the schedule"

STUB_SERVICES="game00" STUB_EXEC_FAIL=1 run 30s || fail "a failed notice write does not fail the script"
expect_log "notice Server restarting in 30 seconds.
sleep 30" "a failed notice write still sleeps the schedule"
grep -q "could not" "$stubs/stderr" || fail "a failed notice write is logged"
echo "ok - a failed notice write is logged"

for bad in "" "1h" "abc" "30s 1m" "0s"; do
    if STUB_SERVICES="game00" run $bad; then
        fail "rejects steps '$bad'"
    fi
    [ ! -s "$stubs/log" ] || fail "steps '$bad' announce nothing"
done
echo "ok - rejects missing, unknown, non-descending and zero steps"

echo "announce-restart tests passed"
